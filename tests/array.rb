# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

# -----------------------------------------------------------------------
# テスト用モジュール
#
# RTL 入力信号は TestBench レベルの Wire として定義し、
# Module へポートとして接続する。
# これにより _update_pre_active で値が確定してから always_ff が動く。
# -----------------------------------------------------------------------

# シンクロナス RAM（posedge に同期してメモリ読み書き）
class SyncRAM < DeepSveite::Module
  attr_accessor :clk, :we, :waddr, :din, :raddr, :dout
  always_ff :tick, cond: [:clk.posedge]

  def initialize(size: 4, width: 8)
    @mem   = DeepSveite::RegArray.new(width: width, size: size)
    @clk   = DeepSveite::Wire.new
    @we    = DeepSveite::Wire.new
    @waddr = DeepSveite::Wire.new(width: 4)
    @din   = DeepSveite::Wire.new(width: width)
    @raddr = DeepSveite::Wire.new(width: 4)
    @dout  = DeepSveite::Reg.new(width: width)
    super()
  end

  def tick
    @mem[@waddr.w] = @din.w if @we.w == 1
    @dout.r = @mem[@raddr.w]
  end
end

# テストベンチ: 入力 Wire を TestBench レベルで定義してポート接続
class SyncRAMBench < DeepSveite::TestBench
  attr_reader :clk, :we, :waddr, :din, :raddr, :ram

  def initialize(**opts)
    super()
    @clk   = DeepSveite::Wire.new
    @we    = DeepSveite::Wire.new
    @waddr = DeepSveite::Wire.new(width: 4)
    @din   = DeepSveite::Wire.new(width: opts.fetch(:width, 8))
    @raddr = DeepSveite::Wire.new(width: 4)
    @ram   = SyncRAM.new(**opts)
    @ram.clk   = @clk.in
    @ram.we    = @we.in
    @ram.waddr = @waddr.in
    @ram.din   = @din.in
    @ram.raddr = @raddr.in
  end
end

# ルックアップテーブル（組み合わせ回路: sel → out）
class LUTModule < DeepSveite::Module
  attr_accessor :sel, :out
  always_comb :lookup

  def initialize(table)
    @lut = DeepSveite::WireArray.new(width: 8, size: table.size)
    @sel = DeepSveite::Wire.new(width: 4)
    @out = DeepSveite::Wire.new(width: 8)
    table.each_with_index { |v, i| @lut[i] = v }
    super()
  end

  def lookup
    @out.w = @lut[@sel.w]
  end
end

class LUTBench < DeepSveite::TestBench
  attr_reader :clk, :sel, :lut_mod

  def initialize(table)
    super()
    @clk     = DeepSveite::Wire.new
    @sel     = DeepSveite::Wire.new(width: 4)
    @lut_mod = LUTModule.new(table)
    @lut_mod.sel = @sel.in
  end
end

# TLM モジュール: RegArray をソフトウェア的なデータストアとして使用
class TLMStore < DeepSveite::Module
  attr_reader :log

  def initialize
    @store = DeepSveite::RegArray.new(width: 16, size: 8)
    @log   = []
    super()
  end

  process :run
  def run
    @store[0] = 100
    @store[3] = 200
    @store[7] = 300
    @log << @store[0]
    @log << @store[3]
    @log << @store[7]
  end
end

# -----------------------------------------------------------------------

class TestArray < Minitest::Test

  # RegArray: 書き込んだ値を次のクロックで読み出せる
  def test_regarray_write_and_read
    tb  = SyncRAMBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    tb.we.w    = 1
    tb.waddr.w = 1
    tb.din.w   = 42
    n = 0; sim.run { (n += 1) >= 2 }  # 1 posedge で書き込み

    tb.we.w    = 0
    tb.raddr.w = 1
    n = 0; sim.run { (n += 1) >= 2 }  # 1 posedge で読み出し

    assert_equal 42, tb.ram.dout.r
  end

  # RegArray: 同一エッジでの書き込みと読み出しは NBA なので、読み出しは更新前の値
  def test_regarray_read_during_write_returns_old_value
    tb  = SyncRAMBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    tb.we.w    = 1
    tb.waddr.w = 1
    tb.din.w   = 42
    tb.raddr.w = 1
    n = 0; sim.run { (n += 1) >= 2 }  # 1 posedge: 書き込みと読み出しが同時
    assert_equal 0, tb.ram.dout.r

    tb.din.w = 99
    n = 0; sim.run { (n += 1) >= 2 }  # 次の posedge: 前回書いた 42 が読める
    assert_equal 42, tb.ram.dout.r
  end

  # RegArray: 複数のアドレスに個別の値を書き込んで読み出せる
  def test_regarray_multiple_addresses
    tb  = SyncRAMBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    # 全アドレスに書き込む（1アドレスにつき1ポジッジ）
    [[0, 10], [1, 20], [2, 30], [3, 40]].each do |addr, val|
      tb.we.w    = 1
      tb.waddr.w = addr
      tb.din.w   = val
      n = 0; sim.run { (n += 1) >= 2 }
    end

    # 全アドレスから読み出す
    results = (0..3).map do |addr|
      tb.we.w    = 0
      tb.raddr.w = addr
      n = 0; sim.run { (n += 1) >= 2 }
      tb.ram.dout.r
    end

    assert_equal [10, 20, 30, 40], results
  end

  # RegArray: dout（出力レジスタ）は posedge の NBA 後に確定する
  def test_regarray_dout_nba_update
    tb  = SyncRAMBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    # posedge 前: dout はまだ 0
    assert_equal 0, tb.ram.dout.r

    tb.we.w    = 1
    tb.waddr.w = 0
    tb.din.w   = 0xFF
    n = 0; sim.run { (n += 1) >= 2 }  # 1 posedge: 書き込み

    tb.we.w    = 0
    tb.raddr.w = 0
    n = 0; sim.run { (n += 1) >= 2 }  # 1 posedge: 読み出し

    # posedge 後: NBA により dout が確定
    assert_equal 0xFF, tb.ram.dout.r
  end

  # RegArray: ビット幅を指定して作成できる
  def test_regarray_custom_width
    tb  = SyncRAMBench.new(width: 16)
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    tb.we.w    = 1
    tb.waddr.w = 0
    tb.din.w   = 0x1234
    n = 0; sim.run { (n += 1) >= 2 }

    tb.we.w    = 0
    tb.raddr.w = 0
    n = 0; sim.run { (n += 1) >= 2 }

    assert_equal 0x1234, tb.ram.dout.r
  end

  # WireArray: 書き込んだ値を読み出せる
  def test_wirearray_write_and_read
    table = [0xAA, 0xBB, 0xCC, 0xDD]
    tb    = LUTBench.new(table)
    sim   = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    results = table.size.times.map do |i|
      tb.sel.w = i
      n = 0; sim.run { (n += 1) >= 1 }  # 1ステップで組み合わせ回路が評価される
      tb.lut_mod.out.w
    end

    assert_equal table, results
  end

  # WireArray: always_comb でルックアップテーブルとして動作する
  def test_wirearray_as_lookup_table
    table = [10, 20, 30, 40, 50, 60, 70, 80]
    tb    = LUTBench.new(table)
    sim   = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    tb.sel.w = 5
    n = 0; sim.run { (n += 1) >= 1 }

    assert_equal 60, tb.lut_mod.out.w
  end

  # TLM: RegArray をデータストアとして即時読み書きできる
  def test_regarray_in_tlm_module
    store = TLMStore.new

    tb = DeepSveite::TestBench.new
    tb.instance_variable_set(:@store, store)

    sim = DeepSveite::Simulator.new(tb)
    sim.build
    sim.run

    assert_equal [100, 200, 300], store.log
  end

  # 範囲外インデックスの読み書きは IndexError
  def test_out_of_range_index_raises
    reg_array  = DeepSveite::RegArray.new(width: 8, size: 4)
    wire_array = DeepSveite::WireArray.new(width: 8, size: 4)

    [reg_array, wire_array].each do |arr|
      assert_raises(IndexError) { arr[4] }
      assert_raises(IndexError) { arr[-1] }
      assert_raises(IndexError) { arr[4] = 1 }
      assert_raises(IndexError) { arr[-1] = 1 }
    end
  end

  # VCD: RegArray の要素が "name[i]" 形式で出力される
  def test_regarray_appears_in_vcd
    tb  = SyncRAMBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build
    vcd = DeepSveite::VCD.new(sim)

    n = 0; sim.run { (n += 1) >= 4 }

    path = "/tmp/deepsveite_array_vcd_test.vcd"
    vcd.write(path)
    content = File.read(path)
    File.unlink(path)

    assert_match(/\$var reg 8 . mem\[0\] \$end/, content)
    assert_match(/\$var reg 8 . mem\[1\] \$end/, content)
    assert_match(/\$var reg 8 . mem\[3\] \$end/, content)
  end
end
