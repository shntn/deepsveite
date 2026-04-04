require_relative "../lib/deepsveite"

DS = DeepSveite

# VCD サンプル: 4ビットカウンタと非同期リセット
#
# 使い方:
#   1. sim.build の後に VCD.new(sim, filename: "...")
#   2. sim.run でシミュレーション実行
#   3. vcd.write で VCD ファイルを生成
#   VCD クラスを使用しない場合は記録・保存は一切行われない。

class Counter < DS::Module
  attr_accessor :clk, :rst, :q
  always_ff :tick, cond: [:clk.posedge]

  def initialize
    @q = DS::Reg.new(width: 4)
    super()
  end

  def tick
    if @rst.w == 0
      @q.r = 0
    else
      @q.r = (@q.r + 1) & 0xF
    end
  end
end

class Bench < DS::TestBench
  attr_accessor :clk, :rst, :counter

  def initialize
    super()
    @clk     = DS::Wire.new
    @rst     = DS::Wire.new
    @counter = Counter.new
    @counter.clk = @clk.in
    @counter.rst = @rst.in
  end
end

def main
  tb  = Bench.new
  sim = DS::Simulator.new(tb, tb.clk)
  sim.build

  vcd = DS::VCD.new(sim, filename: "examples/counter.vcd")

  tb.rst.w = 1

  n = 0
  sim.run do
    n += 1
    # q が 5 になったらリセット
    tb.rst.w = 0 if tb.clk.w == 1 && tb.counter.q.r == 5
    tb.rst.w = 1 if tb.clk.w == 1 && tb.counter.q.r == 0 && n > 4
    n >= 20
  end

  vcd.write
  puts "VCD を examples/counter.vcd に出力しました。"
end

main
