require_relative "../lib/deepsveite"

DS = DeepSveite

# 非同期リセット付き加算レジスタ
# - posedge clk : dout <= din1 + din2
# - negedge rst  : dout <= 0 (active-low 非同期リセット)
class MyModule < DS::Module
  always_ff :routine,
            cond: [:clk.posedge, :rst.negedge],
            reads: [:din1, :din2, :rst],
            writes: [:dout]

  def initialize(clk, rst, din1, din2, dout)
    @clk  = clk.in
    @rst  = rst.in
    @din1 = din1.in
    @din2 = din2.in
    @dout = dout.out
    super()
  end

  def routine
    if @rst.w == 0       # negedge rst: 非同期リセット（active-low）
      @dout.w = 0
    else                 # posedge clk: 入力を取り込んでレジスタに保持
      @dout.w = @din1.w + @din2.w
    end
  end
end

class Bench < DS::TestBench
  attr_accessor :clk, :rst, :din1, :din2, :dout

  def initialize
    super()
    @clk  = DS::Wire.new
    @rst  = DS::Wire.new
    @din1 = DS::Wire.new(width: 8)
    @din2 = DS::Wire.new(width: 8)
    @dout = DS::Wire.new(width: 8)
    @mod  = MyModule.new(@clk, @rst, @din1, @din2, @dout)
  end
end

def main
  tb  = Bench.new
  sim = DS::Simulator.new(tb)
  sim.build

  tb.rst.w  = 1  # rst deassert（通常動作）
  tb.din1.w = 3
  tb.din2.w = 4

  # posedge clk: dout = 3 + 4 = 7
  tb.clk.w = 1
  sim.step
  print "posedge clk → dout: #{tb.dout.w}\n"

  # negedge rst: dout = 0（非同期リセット）
  tb.rst.w = 0
  sim.step
  print "negedge rst → dout: #{tb.dout.w}\n"

  # rst deassert, clk negedge（条件に含まれないので発火しない）
  tb.rst.w = 1
  tb.din1.w = 10
  tb.clk.w  = 0
  sim.step
  print "negedge clk → dout: #{tb.dout.w}\n"

  # posedge clk: dout = 10 + 4 = 14
  tb.clk.w = 1
  sim.step
  print "posedge clk → dout: #{tb.dout.w}\n"
end

main
