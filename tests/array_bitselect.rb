# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

# always_ff が RegArray の同じ要素にビット単位で書き込む
class BitsFF < DeepSveite::Module
  attr_accessor :clk
  attr_reader :regs, :seen
  always_ff :write, cond: [:clk.posedge]

  def initialize
    @regs = DeepSveite::RegArray.new(width: 8, size: 2)
    @seen = nil
    super()
  end

  def write
    @regs[0, 0] = 1
    @regs[0, 7] = 1
    @regs[1, 0..3] = 0xA
    @seen = @regs[0, 0]   # NBA なので更新前の値
  end
end

# always_comb が WireArray の同じ要素の上位・下位ニブルに書き込む
class BitsComb < DeepSveite::Module
  attr_accessor :hi, :lo
  attr_reader :tbl
  always_comb :fill

  def initialize
    @tbl = DeepSveite::WireArray.new(width: 8, size: 2)
    super()
  end

  def fill
    @tbl[0, 4..7] = @hi.w
    @tbl[0, 0..3] = @lo.w
  end
end

class BitsFFBench < DeepSveite::TestBench
  attr_reader :clk, :dut

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @dut = BitsFF.new
    @dut.clk = @clk.in
  end
end

class BitsCombBench < DeepSveite::TestBench
  attr_reader :clk, :hi, :lo, :dut

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @hi  = DeepSveite::Wire.new(width: 4)
    @lo  = DeepSveite::Wire.new(width: 4)
    @dut = BitsComb.new
    @dut.hi = @hi.in
    @dut.lo = @lo.in
  end
end

class TestArrayBitSelect < Minitest::Test

  [DeepSveite::RegArray, DeepSveite::WireArray].each do |klass|
    name = klass.name.split("::").last.downcase

    # ビットの読み出し
    define_method("test_#{name}_read_bit_and_range") do
      arr = klass.new(width: 8, size: 2)
      arr[0] = 0x55
      assert_equal 1, arr[0, 0]
      assert_equal 0, arr[0, 1]
      assert_equal 5, arr[0, 4..7]
      assert_equal 2, arr[0, 1..2]   # bit1=0, bit2=1 → 0b10
    end

    # プロセス外（TLM / TestBench / initialize）のビット書き込みは即時反映される
    define_method("test_#{name}_write_bit_and_range_outside_process") do
      arr = klass.new(width: 8, size: 2)
      arr[0] = 0x50
      arr[0, 1] = 1
      assert_equal 0x52, arr[0]
      arr[0, 0..3] = 0xF
      assert_equal 0x5F, arr[0]
      arr[0, 6] = 0
      assert_equal 0x1F, arr[0]
      assert_equal 0, arr[1]   # 他の要素には影響しない
    end

    # 書き込みは幅でマスクされる
    define_method("test_#{name}_bit_write_is_masked_to_width") do
      arr = klass.new(width: 4, size: 1)
      arr[0, 7] = 1
      arr[0, 0..7] = 0xFF
      assert_equal 0xF, arr[0]
    end

    # 範囲外のインデックスと不正なビット指定はエラー
    define_method("test_#{name}_invalid_arguments_raise") do
      arr = klass.new(width: 8, size: 2)
      assert_raises(IndexError)    { arr[2, 0] }
      assert_raises(IndexError)    { arr[2, 0] = 1 }
      assert_raises(ArgumentError) { arr[0, "x"] }
      assert_raises(ArgumentError) { arr[0, "x"] = 1 }
    end
  end

  # always_ff 内のビット書き込みは NBA: 同じ要素への複数のビット書き込みが合成され、読み出しは更新前の値
  def test_regarray_bit_writes_in_always_ff_are_nba
    tb  = BitsFFBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    sim.step  # posedge
    assert_equal 0x81, tb.dut.regs[0]
    assert_equal 0xA,  tb.dut.regs[1]
    assert_equal 0,    tb.dut.seen
  end

  # always_comb 内のビット書き込みも、同じ要素への複数の書き込みが合成される
  def test_wirearray_bit_writes_in_always_comb
    tb  = BitsCombBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    tb.hi.w = 0xA
    tb.lo.w = 0x5
    sim.step
    assert_equal 0xA5, tb.dut.tbl[0]

    tb.lo.w = 0x3
    sim.step
    assert_equal 0xA3, tb.dut.tbl[0]
  end
end
