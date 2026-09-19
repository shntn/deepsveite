# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

# 比較式の結果（true / false）を Wire に書く組み合わせ回路
class MaskCompare < DeepSveite::Module
  attr_accessor :a
  attr_reader :gt
  always_comb :compare

  def initialize
    @gt = DeepSveite::Wire.new
    super()
  end

  def compare = @gt.w = @a.w > 3
end

class MaskCompareBench < DeepSveite::TestBench
  attr_reader :clk, :a, :dut

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @a   = DeepSveite::Wire.new(width: 8)
    @dut = MaskCompare.new
    @dut.a = @a.in
  end
end

class TestMask < Minitest::Test

  # Reg のビット・範囲書き込みも幅を超えない
  def test_reg_masks_bit_and_range_write
    reg = DeepSveite::Reg.new(width: 4)
    reg[7] = 1
    reg[0..7] = 0xFF
    reg._update
    assert_equal 0xF, reg.r
  end

  # 範囲書き込みは、範囲外のビットを保持したまま幅でマスクされる
  def test_reg_range_write_keeps_other_bits
    reg = DeepSveite::Reg.new(width: 8)
    reg.r = 0xF0
    reg._update
    reg[0..3] = 0x1F
    reg._update
    assert_equal 0xFF, reg.r
  end

  # Reg の true / false は 1 / 0 になる
  def test_reg_converts_boolean
    reg = DeepSveite::Reg.new
    reg.r = true
    reg._update
    assert_equal 1, reg.r

    reg.r = false
    reg._update
    assert_equal 0, reg.r
  end

  # 比較式の結果を Wire に書くと 1 / 0 になる
  def test_comparison_result_becomes_bit
    tb  = MaskCompareBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    tb.a.w = 5
    sim.step
    assert_equal 1, tb.dut.gt.w

    tb.a.w = 2
    sim.step
    assert_equal 0, tb.dut.gt.w
  end

  # 整数以外のオブジェクトは変換せずそのまま保持される
  def test_non_integer_value_passes_through
    wire = DeepSveite::Wire.new(width: 8)
    wire.w = "payload"
    wire._update
    assert_equal "payload", wire.w
  end

  # RegArray の値は幅でマスクされる
  def test_regarray_masks_value
    array = DeepSveite::RegArray.new(width: 4, size: 2)
    array[0] = 0x1F
    array[1] = -1
    assert_equal 0xF, array[0]
    assert_equal 0xF, array[1]
  end

  # WireArray の値は幅でマスクされる
  def test_wirearray_masks_value
    array = DeepSveite::WireArray.new(width: 4, size: 2)
    array[0] = 0x1F
    array[1] = -1
    assert_equal 0xF, array[0]
    assert_equal 0xF, array[1]
  end
end
