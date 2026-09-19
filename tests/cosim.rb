# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

# TLM process が Wire を駆動し、RTL の always_comb がそれをコピーする
class CosimMirror < DeepSveite::Module
  attr_accessor :sig
  attr_reader :mirror
  always_comb :copy

  def initialize
    @mirror = DeepSveite::Wire.new
    super()
  end

  def copy = @mirror.w = @sig.w
end

class CosimTlmDriver < DeepSveite::Module
  attr_accessor :sig
  process :run

  def run
    @sig.w = 1
    wait
    @sig.w = 0
  end
end

class CosimWireBench < DeepSveite::TestBench
  attr_reader :clk, :mirror_mod

  def initialize
    super()
    @clk        = DeepSveite::Wire.new
    @sig        = DeepSveite::Wire.new
    @driver     = CosimTlmDriver.new
    @mirror_mod = CosimMirror.new
    @driver.sig     = @sig.out
    @mirror_mod.sig = @sig.in
  end
end

# RTL カウンタの Reg を TLM process が毎サイクル読む
class CosimCounter < DeepSveite::Module
  attr_accessor :clk
  attr_reader :count
  always_ff :tick, cond: [:clk.posedge]

  def initialize
    @count = DeepSveite::Reg.new(width: 8)
    super()
  end

  def tick = @count.r = @count.r + 1
end

class CosimMonitor < DeepSveite::Module
  attr_accessor :counter
  attr_reader :log
  process :run

  def initialize
    @log = []
    super()
  end

  def run
    3.times do
      @log << @counter.count.r
      wait
    end
  end
end

class CosimMonitorBench < DeepSveite::TestBench
  attr_reader :clk, :counter, :monitor

  def initialize
    super()
    @clk     = DeepSveite::Wire.new
    @counter = CosimCounter.new
    @monitor = CosimMonitor.new
    @counter.clk     = @clk.in
    @monitor.counter = @counter
  end
end

# TLM process が Reg に書き込む
class CosimRegWriter < DeepSveite::Module
  attr_reader :reg
  process :run

  def initialize
    @reg = DeepSveite::Reg.new(width: 8)
    super()
  end

  def run
    @reg.r = 9
  end
end

class CosimRegWriterBench < DeepSveite::TestBench
  attr_reader :clk, :writer

  def initialize
    super()
    @clk    = DeepSveite::Wire.new
    @writer = CosimRegWriter.new
  end
end

# CLAUDE.md の協調シミュレーション例と同じ構成
class CosimEnableCounter < DeepSveite::Module
  attr_accessor :clk, :enable
  attr_reader :count
  always_ff :tick, cond: [:clk.posedge]

  def initialize
    @count = DeepSveite::Reg.new(width: 8)
    super()
  end

  def tick = (@count.r = @count.r + 1 if @enable.w == 1)
end

class CosimController < DeepSveite::Module
  attr_accessor :enable
  process :run

  def run
    @enable.w = 1
    5.times { wait }
    @enable.w = 0
  end
end

class CosimEnableBench < DeepSveite::TestBench
  attr_reader :clk, :counter

  def initialize
    super()
    @clk        = DeepSveite::Wire.new
    @enable_sig = DeepSveite::Wire.new
    @ctrl       = CosimController.new
    @counter    = CosimEnableCounter.new
    @ctrl.enable    = @enable_sig.out
    @counter.clk    = @clk.in
    @counter.enable = @enable_sig.in
  end
end

class TestCosim < Minitest::Test

  # TLM が Wire に書いた値は、次の step で RTL 側に伝わる
  def test_tlm_write_reaches_rtl_on_next_step
    tb  = CosimWireBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    sim.step  # posedge: TLM process が起床キューに入る
    assert_equal 0, tb.mirror_mod.mirror.w

    sim.step  # negedge: TLM process が sig = 1 を書く（RTL への反映は次の step）
    assert_equal 0, tb.mirror_mod.mirror.w

    sim.step  # posedge: sig = 1 が RTL の always_comb に伝わる
    assert_equal 1, tb.mirror_mod.mirror.w

    sim.step  # negedge: TLM process が sig = 0 を書く
    assert_equal 1, tb.mirror_mod.mirror.w

    sim.step  # posedge
    assert_equal 0, tb.mirror_mod.mirror.w
  end

  # RTL の Reg の値を、TLM process が毎サイクル読み取れる
  def test_tlm_reads_rtl_reg
    tb  = CosimMonitorBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    6.times { sim.step }

    assert_equal [1, 2, 3], tb.monitor.log
  end

  # TLM から Reg に書いた値は、次の step の NBA 領域で確定する
  def test_tlm_write_to_reg_is_applied_on_next_step
    tb  = CosimRegWriterBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    sim.step  # posedge
    sim.step  # negedge: TLM process が reg.r = 9 を書く
    assert_equal 0, tb.writer.reg.r

    sim.step  # posedge: NBA 領域で確定
    assert_equal 9, tb.writer.reg.r
  end

  # TLM が enable を立てている間だけ RTL カウンタが進む
  def test_enable_driven_by_tlm_gates_rtl_counter
    tb  = CosimEnableBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    n = 0
    sim.run { (n += 1) >= 20 }

    assert_equal 5, tb.counter.count.r
  end
end
