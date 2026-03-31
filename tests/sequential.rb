# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

# D フリップフロップ: posedge clk で d の値を取り込む
class DFF < DeepSveite::Module
  always_ff :latch, cond: [:clk.posedge]

  attr_reader :q

  def initialize(clk, d)
    @clk = clk.in
    @d   = d.in
    @q   = DeepSveite::Reg.new(width: 8)
    super()
  end

  def latch
    @q.r = @d.w
  end
end

class DFFBench < DeepSveite::TestBench
  attr_accessor :clk, :d, :dff

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @d   = DeepSveite::Wire.new(width: 8)
    @dff = DFF.new(@clk, @d)
  end
end

# カウンタ: posedge clk でインクリメント
class SequentialCounter < DeepSveite::Module
  always_ff :count_up, cond: [:clk.posedge]

  attr_reader :q

  def initialize(clk)
    @clk = clk.in
    @q   = DeepSveite::Reg.new(width: 8)
    super()
  end

  def count_up
    @q.r = @q.r + 1
  end
end

class SequentialCounterBench < DeepSveite::TestBench
  attr_accessor :clk, :counter

  def initialize
    super()
    @clk     = DeepSveite::Wire.new
    @counter = SequentialCounter.new(@clk)
  end
end

# リセット付きカウンタ: posedge clk でインクリメント、negedge rst でリセット
class ResettableCounter < DeepSveite::Module
  always_ff :count_up, cond: [:clk.posedge, :rst.negedge]

  attr_reader :q

  def initialize(clk, rst)
    @clk = clk.in
    @rst = rst.in
    @q   = DeepSveite::Reg.new(width: 8)
    super()
  end

  def count_up
    if @rst.w == 0
      @q.r = 0
    else
      @q.r = @q.r + 1
    end
  end
end

class ResettableCounterBench < DeepSveite::TestBench
  attr_accessor :clk, :rst, :counter

  def initialize
    super()
    @clk     = DeepSveite::Wire.new
    @rst     = DeepSveite::Wire.new
    @counter = ResettableCounter.new(@clk, @rst)
  end
end

class TestSequential < Minitest::Test

  # posedge clk で入力値を取り込む
  def test_dff_captures_on_posedge
    tb  = DFFBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    tb.d.w = 5
    sim.step  # clk: 0→1 (posedge) → latch 発火

    assert_equal 5, tb.dff.q.r
  end

  # negedge clk では取り込まれない
  def test_dff_no_capture_on_negedge
    tb  = DFFBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    tb.d.w = 5
    sim.step  # clk: 0→1 (posedge) → q = 5

    tb.d.w = 9
    sim.step  # clk: 1→0 (negedge) → latch は発火しない

    assert_equal 5, tb.dff.q.r
  end

  # posedge のたびにカウントアップし、negedge では変化しない
  def test_counter_increments_on_posedge_only
    tb  = SequentialCounterBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    sim.step; assert_equal 1, tb.counter.q.r  # posedge → +1
    sim.step; assert_equal 1, tb.counter.q.r  # negedge → 変化なし
    sim.step; assert_equal 2, tb.counter.q.r  # posedge → +1
    sim.step; assert_equal 2, tb.counter.q.r  # negedge → 変化なし
    sim.step; assert_equal 3, tb.counter.q.r  # posedge → +1
  end

  # posedge clk と同時に negedge rst が来たときリセットされる
  def test_reset_on_negedge_rst_with_posedge_clk
    tb  = ResettableCounterBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    tb.rst.w = 1
    sim.step; assert_equal 1, tb.counter.q.r  # posedge, rst=1 → count_up
    sim.step; assert_equal 1, tb.counter.q.r  # negedge, 変化なし
    sim.step; assert_equal 2, tb.counter.q.r  # posedge → count_up

    # posedge clk と同時に rst を落とす → count_up がリセット処理を実行
    tb.rst.w = 0
    sim.step  # clk: 0→1 (posedge), rst: 1→0 (negedge) → q = 0
    assert_equal 0, tb.counter.q.r
  end

  # negedge rst 単独でもリセットされる (clk の posedge なし)
  def test_reset_on_negedge_rst_alone
    tb  = ResettableCounterBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    tb.rst.w = 1
    sim.step; assert_equal 1, tb.counter.q.r  # posedge → count_up

    # negedge clk のタイミングで rst を落とす (clk posedge は起きない)
    tb.rst.w = 0
    sim.step  # clk: 1→0 (negedge), rst: 1→0 (negedge) → count_up がリセット処理を実行
    assert_equal 0, tb.counter.q.r
  end
end
