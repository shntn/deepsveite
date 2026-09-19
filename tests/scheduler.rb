# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

# カウンタ(Reg) → 組み合わせ回路2段 の構成
class RegToComb < DeepSveite::Module
  attr_accessor :clk
  attr_reader :count, :double, :quad
  always_ff :tick, cond: [:clk.posedge]
  always_comb :calc_double, reads: [:count]
  always_comb :calc_quad,   reads: [:double]

  def initialize
    @clk    = DeepSveite::Wire.new
    @count  = DeepSveite::Reg.new(width: 8)
    @double = DeepSveite::Wire.new(width: 8)
    @quad   = DeepSveite::Wire.new(width: 8)
    super()
  end

  def tick        = @count.r = @count.r + 1
  def calc_double = @double.w = @count.r * 2
  def calc_quad   = @quad.w = @double.w * 2
end

class RegToCombBench < DeepSveite::TestBench
  attr_reader :clk, :dut

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @dut = RegToComb.new
    @dut.clk = @clk.in
  end
end

# 2段シフトレジスタ: NBA により q2 は q1 の「更新前」の値を取り込む
class ShiftReg < DeepSveite::Module
  attr_accessor :clk, :d
  attr_reader :q1, :q2
  always_ff :shift, cond: [:clk.posedge]

  def initialize
    @clk = DeepSveite::Wire.new
    @d   = DeepSveite::Wire.new(width: 8)
    @q1  = DeepSveite::Reg.new(width: 8)
    @q2  = DeepSveite::Reg.new(width: 8)
    super()
  end

  def shift
    @q2.r = @q1.r
    @q1.r = @d.w
  end
end

class ShiftRegBench < DeepSveite::TestBench
  attr_reader :clk, :d, :dut

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @d   = DeepSveite::Wire.new(width: 8)
    @dut = ShiftReg.new
    @dut.clk = @clk.in
    @dut.d   = @d.in
  end
end

class TestScheduler < Minitest::Test

  # Reg の更新に反応する組み合わせ回路は、同じ step 内で収束する
  def test_comb_settles_in_same_step_after_reg_update
    tb  = RegToCombBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    sim.step  # posedge: count 0 -> 1
    assert_equal 1, tb.dut.count.r
    assert_equal 2, tb.dut.double.w
    assert_equal 4, tb.dut.quad.w

    sim.step  # negedge: 変化なし
    sim.step  # posedge: count 1 -> 2
    assert_equal 2, tb.dut.count.r
    assert_equal 4, tb.dut.double.w
    assert_equal 8, tb.dut.quad.w
  end

  # always_ff 内の Reg 同士の代入は NBA: 全 Reg が更新前の値を読む
  def test_shift_register_uses_old_values
    tb  = ShiftRegBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    tb.d.w = 7
    sim.step  # posedge
    assert_equal 7, tb.dut.q1.r
    assert_equal 0, tb.dut.q2.r

    sim.step  # negedge
    tb.d.w = 9
    sim.step  # posedge
    assert_equal 9, tb.dut.q1.r
    assert_equal 7, tb.dut.q2.r
  end
end
