require_relative "../lib/deepsveite"

DS = DeepSveite

# 4ビット カウンタ（非同期 active-low リセット付き）
class Counter < DS::Module
  always_ff :count_up,
            cond: [:clk.posedge, :rst.negedge],
            reads: [:rst],
            writes: [:q]

  def initialize(clk, rst, q)
    @clk = clk.in
    @rst = rst.in
    @q   = q       # 読み書き両用（カウンタは自分の値を参照しながら更新する）
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
  attr_accessor :clk, :rst, :q

  def initialize
    super()
    @clk = DS::Wire.new
    @rst = DS::Wire.new
    @q   = DS::Reg.new(width: 4)
    @counter = Counter.new(@clk, @rst, @q)
  end
end

def main
  tb  = Bench.new
  sim = DS::Simulator.new(tb, tb.clk)
  sim.build

  tb.rst.w = 1

  sim.run do
    if tb.clk.w == 1               # posedge のみ
      print "q = #{tb.q.r}\n"
      tb.rst.w = 0 if tb.q.r == 3  # q が 3 になったらリセット
    end
    tb.q.r == 0 && tb.clk.w == 1   # リセット後の posedge で終了
  end
end

main
