# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

# -----------------------------------------------------------------------
# テスト用モジュール
# -----------------------------------------------------------------------

# 同一 Wire に書き込む always_comb プロセスを2つ持つ構成
class DriverA < DeepSveite::Module
  attr_accessor :trigger, :out
  always_comb :drive, reads: [:trigger]

  def initialize
    @trigger = DeepSveite::Wire.new
    @out     = DeepSveite::Wire.new
    super()
  end

  def drive
    @out.w = 1
  end
end

class DriverB < DeepSveite::Module
  attr_accessor :trigger, :out
  always_comb :drive, reads: [:trigger]

  def initialize
    @trigger = DeepSveite::Wire.new
    @out     = DeepSveite::Wire.new
    super()
  end

  def drive
    @out.w = 0
  end
end

# shared_out を共有する TestBench
class MultiCombBench < DeepSveite::TestBench
  attr_reader :clk, :trigger, :shared_out, :da, :db

  def initialize
    super()
    @clk        = DeepSveite::Wire.new
    @trigger    = DeepSveite::Wire.new
    @shared_out = DeepSveite::Wire.new
    @da = DriverA.new
    @db = DriverB.new
    @da.trigger = @trigger.in
    @da.out     = @shared_out.out   # DriverA が shared_out を駆動
    @db.trigger = @trigger.in
    @db.out     = @shared_out.out   # DriverB も同じ shared_out を駆動 → 複数ドライバ
  end
end

# 同一 Reg に書き込む always_ff プロセスを2つ持つ構成
class FFDriverA < DeepSveite::Module
  attr_accessor :clk, :out
  always_ff :drive, cond: [:clk.posedge]

  def initialize
    @clk = DeepSveite::Wire.new
    @out = DeepSveite::Reg.new
    super()
  end

  def drive
    @out.r = 1
  end
end

class FFDriverB < DeepSveite::Module
  attr_accessor :clk, :out
  always_ff :drive, cond: [:clk.posedge]

  def initialize
    @clk = DeepSveite::Wire.new
    @out = DeepSveite::Reg.new
    super()
  end

  def drive
    @out.r = 0
  end
end

class MultiFFBench < DeepSveite::TestBench
  attr_reader :clk, :shared_reg, :fa, :fb

  def initialize
    super()
    @clk        = DeepSveite::Wire.new
    @shared_reg = DeepSveite::Reg.new
    @fa = FFDriverA.new
    @fb = FFDriverB.new
    @fa.clk = @clk.in
    @fa.out = @shared_reg.out
    @fb.clk = @clk.in
    @fb.out = @shared_reg.out
  end
end

# 同一プロセスが複数回書く（正常ケース）
class SingleDriverMultiWrite < DeepSveite::Module
  attr_accessor :sel, :out
  always_comb :drive, reads: [:sel]

  def initialize
    @sel = DeepSveite::Wire.new
    @out = DeepSveite::Wire.new(width: 8)
    super()
  end

  def drive
    @out.w = 1   # 1回目
    @out.w = 2   # 2回目（同一プロセスなので OK）
  end
end

class SingleDriverBench < DeepSveite::TestBench
  attr_reader :clk, :sel, :mod

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @sel = DeepSveite::Wire.new
    @mod = SingleDriverMultiWrite.new
    @mod.sel = @sel.in
  end
end

# -----------------------------------------------------------------------

class TestMultiDriver < Minitest::Test

  # 異なる always_comb プロセスが同一 Wire に書く → RuntimeError
  def test_multiple_comb_drivers_raises
    tb  = MultiCombBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    assert_raises(RuntimeError) do
      tb.trigger.w = 1
      sim.step
    end
  end

  # 異なる always_ff プロセスが同一 Reg に書く → RuntimeError
  def test_multiple_ff_drivers_raises
    tb  = MultiFFBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    assert_raises(RuntimeError) do
      sim.step   # posedge で両 always_ff が起動
    end
  end

  # 同一プロセスが同一信号に複数回書く → 例外なし（最終値が採用）
  def test_single_process_multiple_writes_ok
    tb  = SingleDriverBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    tb.sel.w = 1
    sim.step   # 例外が出なければ OK
    assert_equal 2, tb.mod.out.w
  end

  # TestBench から直接書く → 例外なし（プロセスコンテキスト外）
  def test_testbench_direct_write_ok
    tb  = SingleDriverBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    # プロセス外から直接書いても例外が出ない
    tb.sel.w = 0
    sim.step
    tb.sel.w = 1
    sim.step
  end

  # エラーメッセージに信号名と両プロセス名が含まれる
  def test_error_message_contains_signal_and_process_names
    tb  = MultiCombBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    err = assert_raises(RuntimeError) do
      tb.trigger.w = 1
      sim.step
    end

    assert_includes err.message, "shared_out"
    assert_includes err.message, "DriverA#drive"
    assert_includes err.message, "DriverB#drive"
  end
end
