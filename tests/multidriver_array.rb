# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

# 別々の always_comb が WireArray の同じ要素に書く
class MdArrayComb < DeepSveite::Module
  attr_accessor :trigger
  always_comb :drive_a, reads: [:trigger]
  always_comb :drive_b, reads: [:trigger]

  def initialize(index_b)
    @index_b = index_b
    @tbl     = DeepSveite::WireArray.new(width: 8, size: 2)
    super()
  end

  def drive_a = @tbl[0] = 1
  def drive_b = @tbl[@index_b] = 2
end

# 別々の always_ff が RegArray の同じ要素に書く
class MdArrayFF < DeepSveite::Module
  attr_accessor :clk
  always_ff :write_a, cond: [:clk.posedge]
  always_ff :write_b, cond: [:clk.posedge]

  def initialize
    @mem = DeepSveite::RegArray.new(width: 8, size: 2)
    super()
  end

  def write_a = @mem[0] = 1
  def write_b = @mem[0] = 2
end

# 同じ always_comb が同じ要素に複数回書く（正常）
class MdArraySingle < DeepSveite::Module
  attr_accessor :trigger
  attr_reader :tbl
  always_comb :drive, reads: [:trigger]

  def initialize
    @tbl = DeepSveite::WireArray.new(width: 8, size: 2)
    super()
  end

  def drive
    @tbl[0] = 1
    @tbl[0] = 2
  end
end

class MdArrayBench < DeepSveite::TestBench
  attr_reader :clk, :trigger, :dut

  def initialize(dut)
    super()
    @clk     = DeepSveite::Wire.new
    @trigger = DeepSveite::Wire.new
    @dut     = dut
    @dut.trigger = @trigger.in if @dut.respond_to?(:trigger=)
    @dut.clk     = @clk.in     if @dut.respond_to?(:clk=)
  end
end

class TestMultiDriverArray < Minitest::Test

  def build(dut)
    tb  = MdArrayBench.new(dut)
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build
    [tb, sim]
  end

  # 別のプロセスが WireArray の同じ要素に書くと多重ドライバ
  def test_two_comb_processes_writing_same_wirearray_element_raise
    tb, sim = build(MdArrayComb.new(0))

    tb.trigger.w = 1
    err = assert_raises(RuntimeError) { sim.step }
    assert_includes err.message, "tbl[0]"
    assert_includes err.message, "MdArrayComb#drive_a"
    assert_includes err.message, "MdArrayComb#drive_b"
  end

  # 別のプロセスでも、書く要素が違えば問題ない
  def test_two_comb_processes_writing_different_elements_are_ok
    tb, sim = build(MdArrayComb.new(1))

    tb.trigger.w = 1
    sim.step
  end

  # 別の always_ff が RegArray の同じ要素に書くと多重ドライバ
  def test_two_ff_processes_writing_same_regarray_element_raise
    _tb, sim = build(MdArrayFF.new)

    err = assert_raises(RuntimeError) { sim.step }
    assert_includes err.message, "mem[0]"
  end

  # 同じプロセスが同じ要素に複数回書くのは正常で、最後の値が有効
  def test_single_process_multiple_writes_to_element_are_ok
    dut = MdArraySingle.new
    tb, sim = build(dut)

    tb.trigger.w = 1
    sim.step
    assert_equal 2, dut.tbl[0]
  end
end
