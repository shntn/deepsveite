require_relative "../lib/deepsveite"

DS = DeepSveite

# ビットセレクト / パートセレクトのサンプル
#
# Wire / Reg の [] でビット単位・範囲単位の読み書きができる。
#   signal[n]          ビット n を読み出す (0 or 1)
#   signal[lo..hi]     ビット lo〜hi を読み出す
#   signal[n] = v      ビット n を書き込む (他のビットは保持)
#   signal[lo..hi] = v ビット lo〜hi に書き込む (他のビットは保持)

# ---- Wire サンプル ----
# 8ビット bus を上位4ビット / 下位4ビットに分けて処理するモジュール

class NibbleSwap < DS::Module
  attr_accessor :din, :dout
  always_comb :swap, reads: [:din]

  # 上位ニブルと下位ニブルを入れ替えて出力する
  def swap
    @dout[0..3] = @din[4..7]
    @dout[4..7] = @din[0..3]
  end
end

class BitMonitor < DS::Module
  attr_accessor :bus
  always_comb :show, reads: [:bus]

  def show
    val = @bus.w
    puts "bus = 0b#{val.to_s(2).rjust(8, "0")}  " \
         "upper=0x#{@bus[4..7].to_s(16)}  lower=0x#{@bus[0..3].to_s(16)}  " \
         "bit4=#{@bus[4]}  bit7=#{@bus[7]}"
  end
end

class WireBench < DS::TestBench
  attr_accessor :din, :dout

  def initialize
    super()
    @din  = DS::Wire.new(init: 0, width: 8)
    @dout = DS::Wire.new(init: 0, width: 8)
    @swap = NibbleSwap.new
    @mon  = BitMonitor.new
    @swap.din  = @din.in
    @swap.dout = @dout.out
    @mon.bus   = @dout.in
  end
end

def wire_sample
  puts "=== Wire ビットセレクト サンプル ==="
  tb  = WireBench.new
  sim = DS::Simulator.new(tb)
  sim.build

  puts "--- din = 0xAB (1010_1011) ---"
  tb.din.w = 0xAB
  sim.step

  puts "--- ビット単位書き込み: din[7]=0, din[0]=0 ---"
  tb.din[7] = 0
  tb.din[0] = 0
  sim.step

  puts "--- パートセレクト書き込み: din[4..7]=0xF ---"
  tb.din[4..7] = 0xF
  sim.step
  puts
end

# ---- Reg サンプル ----
# 8ビット status レジスタをビット操作で管理するモジュール
#   bit 0   : ready フラグ（毎クロック トグル）
#   bit 4〜7: サイクルカウント（4ビット、毎クロック +1）

class StatusReg < DS::Module
  attr_accessor :clk, :status
  always_ff :update, cond: [:clk.posedge]

  def update
    @status[0]    = @status[0] == 0 ? 1 : 0
    @status[4..7] = (@status[4..7] + 1) & 0xF
  end
end

class RegBench < DS::TestBench
  attr_accessor :clk, :status_mod

  def initialize
    super()
    @clk        = DS::Wire.new
    @status_mod = StatusReg.new
    @status_mod.clk    = @clk.in
    @status_mod.status = DS::Reg.new(width: 8)
  end
end

def reg_sample
  puts "=== Reg ビットセレクト サンプル ==="
  tb  = RegBench.new
  sim = DS::Simulator.new(tb, tb.clk)
  sim.build

  6.times do
    sim.step
    next unless tb.clk.w == 1
    s = tb.status_mod.status
    puts "status = 0b#{s.r.to_s(2).rjust(8, "0")}  " \
         "ready=#{s[0]}  cycle_count=#{s[4..7]}"
  end
  puts
end

wire_sample
reg_sample
