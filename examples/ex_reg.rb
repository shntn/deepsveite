require_relative "../lib/deepsveite"

DS = DeepSveite

# 4ビット カウンタ（非同期 active-low リセット付き）
class Counter < DS::Module
  attr_accessor :q
  always_ff :count_up,
            cond: [:clk.posedge, :rst.negedge]

  def initialize(clk, rst, q)
    @clk = clk.in
    @rst = rst.in
    @q   = DS::Reg.new(width: 4)       # 読み書き両用（カウンタは自分の値を参照しながら更新する）
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

class Bench < DS::TestBench
  attr_accessor :clk, :rst, :counter

  def initialize
    super()
    @clk = DS::Wire.new
    @rst = DS::Wire.new
    @counter = Counter.new(@clk, @rst, @q)
  end
end

def main
  tb  = Bench.new
  sim = DS::Simulator.new(tb, tb.clk)
  sim.build

  tb.rst.w = 1

  7.times do
    sim.step
    if tb.clk.w == 1                                # posedge のみ
      print "q = #{tb.counter.q.r}\n"
      tb.rst.w = 0 if tb.counter.q.r == 3           # q が 3 になったらリセット
    end
  end
end

main
