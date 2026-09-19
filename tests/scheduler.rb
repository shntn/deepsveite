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

# always_comb が WireArray の要素を書き、別の always_comb がそれを読む（reads: 省略）
class WireArrayChain < DeepSveite::Module
  attr_accessor :a
  attr_reader :out
  always_comb :fill
  always_comb :read_back

  def initialize
    @tbl = DeepSveite::WireArray.new(width: 8, size: 2)
    @a   = DeepSveite::Wire.new(width: 8)
    @out = DeepSveite::Wire.new(width: 8)
    super()
  end

  def fill      = @tbl[0] = @a.w + 1
  def read_back = @out.w = @tbl[0] * 2
end

# RegArray を書く always_ff と、非同期に読む always_comb（レジスタファイル）
class RegFile < DeepSveite::Module
  attr_accessor :clk, :we, :waddr, :din, :raddr
  attr_reader :rdata
  always_ff   :write, cond: [:clk.posedge]
  always_comb :read

  def initialize
    @regs  = DeepSveite::RegArray.new(width: 8, size: 4)
    @clk   = DeepSveite::Wire.new
    @we    = DeepSveite::Wire.new
    @waddr = DeepSveite::Wire.new(width: 2)
    @din   = DeepSveite::Wire.new(width: 8)
    @raddr = DeepSveite::Wire.new(width: 2)
    @rdata = DeepSveite::Wire.new(width: 8)
    super()
  end

  def write = (@regs[@waddr.w] = @din.w if @we.w == 1)
  def read  = @rdata.w = @regs[@raddr.w]
end

# TestBench から WireArray を書き換え、それを読む always_comb
class ExternalTable < DeepSveite::Module
  attr_accessor :sel
  attr_reader :out, :table
  always_comb :lookup

  def initialize
    @table = DeepSveite::WireArray.new(width: 8, size: 4)
    @sel   = DeepSveite::Wire.new(width: 2)
    @out   = DeepSveite::Wire.new(width: 8)
    super()
  end

  def lookup = @out.w = @table[@sel.w]
end

class ArraySensitivityBench < DeepSveite::TestBench
  attr_reader :clk, :a, :chain, :rf_clk, :rf, :sel, :ext

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @a   = DeepSveite::Wire.new(width: 8)
    @chain = WireArrayChain.new
    @chain.a = @a.in

    @rf = RegFile.new
    @rf.clk   = @clk.in
    @rf.we    = (@we    = DeepSveite::Wire.new).in
    @rf.waddr = (@waddr = DeepSveite::Wire.new(width: 2)).in
    @rf.din   = (@din   = DeepSveite::Wire.new(width: 8)).in
    @rf.raddr = (@raddr = DeepSveite::Wire.new(width: 2)).in

    @sel = DeepSveite::Wire.new(width: 2)
    @ext = ExternalTable.new
    @ext.sel = @sel.in
  end

  attr_reader :we, :waddr, :din, :raddr
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

  # always_comb が書いた WireArray の要素を、別の always_comb が読んで再評価される
  def test_comb_reads_wirearray_written_by_another_comb
    tb  = ArraySensitivityBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    tb.a.w = 4
    sim.step
    assert_equal 10, tb.chain.out.w   # (4 + 1) * 2

    tb.a.w = 9
    sim.step
    assert_equal 20, tb.chain.out.w   # (9 + 1) * 2
  end

  # RegArray の更新に反応して、非同期読み出しの always_comb が同じ step で再評価される
  def test_comb_reads_regarray_after_ff_write
    tb  = ArraySensitivityBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    tb.we.w = 1; tb.waddr.w = 2; tb.din.w = 77; tb.raddr.w = 2
    sim.step  # posedge: regs[2] <= 77 (NBA) → rdata が同じ step で 77 になる
    assert_equal 77, tb.rf.rdata.w
  end

  # TestBench（RTL プロセス外）が WireArray を書き換えると、次の step で always_comb が再評価される
  def test_comb_reevaluated_when_testbench_writes_wirearray
    tb  = ArraySensitivityBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    tb.sel.w = 1
    sim.step
    assert_equal 0, tb.ext.out.w

    tb.ext.table[1] = 55
    sim.step
    assert_equal 55, tb.ext.out.w
  end
end