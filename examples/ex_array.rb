require_relative "../lib/deepsveite"

DS = DeepSveite

# ==========================================================================
# デモ 1: RegArray — シンクロナス RAM
#
#   TestBench レベルの Wire をポートとして接続することで、
#   _update_pre_active により clk の posedge 前に入力値が確定する。
#
#   動作:
#     posedge : we == 1 なら mem[waddr] ← din
#               dout ← mem[raddr]  （同クロックで読み書きが重なった場合は
#                                    書き込み後の値を返す — write-first）
# ==========================================================================

class SyncRAM < DS::Module
  attr_accessor :clk, :we, :waddr, :din, :raddr, :dout
  always_ff :tick, cond: [:clk.posedge]

  def initialize(size: 8, width: 8)
    @mem   = DS::RegArray.new(width: width, size: size)
    @clk   = DS::Wire.new
    @we    = DS::Wire.new
    @waddr = DS::Wire.new(width: 4)
    @din   = DS::Wire.new(width: width)
    @raddr = DS::Wire.new(width: 4)
    @dout  = DS::Reg.new(width: width)
    super()
  end

  def tick
    @mem[@waddr.w] = @din.w if @we.w == 1
    @dout.r = @mem[@raddr.w]
  end
end

class RAMBench < DS::TestBench
  attr_reader :clk, :we, :waddr, :din, :raddr, :ram

  def initialize
    super()
    @clk   = DS::Wire.new
    @we    = DS::Wire.new
    @waddr = DS::Wire.new(width: 4)
    @din   = DS::Wire.new(width: 8)
    @raddr = DS::Wire.new(width: 4)
    @ram   = SyncRAM.new
    @ram.clk   = @clk.in
    @ram.we    = @we.in
    @ram.waddr = @waddr.in
    @ram.din   = @din.in
    @ram.raddr = @raddr.in
  end
end

def demo_ram
  puts "=== デモ 1: RegArray (シンクロナス RAM) ==="

  tb  = RAMBench.new
  sim = DS::Simulator.new(tb, tb.clk)
  sim.build
  vcd = DS::VCD.new(sim, filename: "examples/ram.vcd")

  # --- 書き込みフェーズ ---
  writes = { 0 => 0x11, 1 => 0x22, 2 => 0x33, 3 => 0x44,
             4 => 0x55, 5 => 0x66, 6 => 0x77, 7 => 0x88 }

  tb.we.w = 1
  writes.each do |addr, data|
    tb.waddr.w = addr
    tb.din.w   = data
    n = 0; sim.run { (n += 1) >= 2 }
    printf "  write mem[%d] = 0x%02X\n", addr, data
  end

  # --- 読み出しフェーズ ---
  tb.we.w = 0
  puts ""
  writes.each_key do |addr|
    tb.raddr.w = addr
    n = 0; sim.run { (n += 1) >= 2 }
    printf "  read  mem[%d] = 0x%02X\n", addr, tb.ram.dout.r
  end

  vcd.write
  puts "\nVCD を examples/ram.vcd に出力しました。"
  puts ""
end

# ==========================================================================
# デモ 2: WireArray — パレットルックアップ（組み合わせ回路）
#
#   WireArray に定数テーブルを初期値として書き込み、
#   always_comb で sel → out に変換するルックアップテーブル。
#
#   用途例: カラーパレット、SIN テーブル、エンコードテーブルなど
# ==========================================================================

class PaletteLUT < DS::Module
  attr_accessor :sel, :r_out, :g_out, :b_out
  always_comb :lookup

  PALETTE = [
    [0xFF, 0x00, 0x00],  # 0: Red
    [0x00, 0xFF, 0x00],  # 1: Green
    [0x00, 0x00, 0xFF],  # 2: Blue
    [0xFF, 0xFF, 0x00],  # 3: Yellow
    [0xFF, 0x00, 0xFF],  # 4: Magenta
    [0x00, 0xFF, 0xFF],  # 5: Cyan
    [0xFF, 0xFF, 0xFF],  # 6: White
    [0x00, 0x00, 0x00],  # 7: Black
  ]

  def initialize
    @r_lut = DS::WireArray.new(width: 8, size: PALETTE.size)
    @g_lut = DS::WireArray.new(width: 8, size: PALETTE.size)
    @b_lut = DS::WireArray.new(width: 8, size: PALETTE.size)
    @sel   = DS::Wire.new(width: 4)
    @r_out = DS::Wire.new(width: 8)
    @g_out = DS::Wire.new(width: 8)
    @b_out = DS::Wire.new(width: 8)

    PALETTE.each_with_index do |(r, g, b), i|
      @r_lut[i] = r
      @g_lut[i] = g
      @b_lut[i] = b
    end
    super()
  end

  def lookup
    @r_out.w = @r_lut[@sel.w]
    @g_out.w = @g_lut[@sel.w]
    @b_out.w = @b_lut[@sel.w]
  end
end

class PaletteBench < DS::TestBench
  attr_reader :clk, :sel, :lut

  def initialize
    super()
    @clk = DS::Wire.new
    @sel = DS::Wire.new(width: 4)
    @lut = PaletteLUT.new
    @lut.sel = @sel.in
  end
end

COLOR_NAMES = %w[Red Green Blue Yellow Magenta Cyan White Black]

def demo_palette
  puts "=== デモ 2: WireArray (パレットルックアップ) ==="

  tb  = PaletteBench.new
  sim = DS::Simulator.new(tb, tb.clk)
  sim.build

  PaletteLUT::PALETTE.each_with_index do |(er, eg, eb), i|
    tb.sel.w = i
    n = 0; sim.run { (n += 1) >= 1 }

    r = tb.lut.r_out.w
    g = tb.lut.g_out.w
    b = tb.lut.b_out.w
    printf "  sel=%d %-8s → R=0x%02X G=0x%02X B=0x%02X  %s\n",
           i, COLOR_NAMES[i], r, g, b,
           (r == er && g == eg && b == eb ? "OK" : "FAIL")
  end
  puts ""
end

# ==========================================================================
# エントリポイント
# ==========================================================================

demo_ram
demo_palette
