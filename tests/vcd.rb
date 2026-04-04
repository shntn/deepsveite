# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

# -----------------------------------------------------------------------
# テスト用モジュール
#
# 4ビットカウンタ: clk の posedge ごとに q をインクリメントする
# -----------------------------------------------------------------------

class VCDCounter < DeepSveite::Module
  attr_accessor :clk, :q
  always_ff :tick, cond: [:clk.posedge]

  def initialize
    @q = DeepSveite::Reg.new(width: 4)
    super()
  end

  def tick
    @q.r = (@q.r + 1) & 0xF
  end
end

class VCDBench < DeepSveite::TestBench
  attr_reader :clk, :counter

  def initialize
    super()
    @clk     = DeepSveite::Wire.new
    @counter = VCDCounter.new
    @counter.clk = @clk.in
  end
end

# -----------------------------------------------------------------------

class TestVCD < Minitest::Test
  VCD_TMP = "/tmp/deepsveite_vcd_test.vcd"

  # VCD ファイルの内容を文字列として取得するヘルパー
  def vcd_content(vcd)
    vcd.write(VCD_TMP)
    File.read(VCD_TMP)
  ensure
    File.unlink(VCD_TMP) rescue nil
  end

  # VCD ファイルに必要なヘッダキーワードが含まれる
  def test_header_keywords
    tb  = VCDBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build
    vcd = DeepSveite::VCD.new(sim)
    n = 0; sim.run { (n += 1) >= 4 }

    content = vcd_content(vcd)
    assert_match(/\$timescale/, content)
    assert_match(/\$date/, content)
    assert_match(/\$version DeepSveite VCD \$end/, content)
    assert_match(/\$enddefinitions \$end/, content)
    assert_match(/\$dumpvars/, content)
  end

  # モジュール階層が $scope ブロックで表現される
  def test_scope_hierarchy
    tb  = VCDBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build
    vcd = DeepSveite::VCD.new(sim)
    n = 0; sim.run { (n += 1) >= 4 }

    content = vcd_content(vcd)
    assert_match(/\$scope module VCDBench \$end/, content)
    assert_match(/\$scope module counter \$end/, content)
    assert_match(/\$upscope \$end/, content)
  end

  # $var 宣言に型・ビット幅・信号名が含まれる
  def test_var_declarations
    tb  = VCDBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build
    vcd = DeepSveite::VCD.new(sim)
    n = 0; sim.run { (n += 1) >= 4 }

    content = vcd_content(vcd)
    # clk は wire 1ビット（ID は任意の1文字）
    assert_match(/\$var wire 1 . clk \$end/, content)
    # q は reg 4ビット
    assert_match(/\$var reg 4 . q \$end/, content)
  end

  # $dumpvars はシミュレーション開始時点（build 直後）の初期値を示す
  # — VCD 生成後にカウンタが進んでも dumpvars セクションは変化しない
  def test_initial_values_in_dumpvars
    tb  = VCDBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build
    vcd = DeepSveite::VCD.new(sim)

    # 8ステップ実行: 4 posedge → q = 4 (b0100)
    n = 0; sim.run { (n += 1) >= 8 }

    content = vcd_content(vcd)
    dumpvars = content[/\$dumpvars(.+?)\$end/m, 1]

    # dumpvars には初期値（ゼロ）が含まれる
    assert_match(/b0000/, dumpvars)
    # 最終値 b0100 (=4) は dumpvars に含まれない
    refute_match(/b0100/, dumpvars)
    # 最終値は変化ログとして $dumpvars 以降に存在する
    assert_match(/b0100/, content)
  end

  # シミュレーション後の変化がタイムスタンプ付きで記録される
  def test_change_records_with_timestamps
    tb  = VCDBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build
    vcd = DeepSveite::VCD.new(sim)
    n = 0; sim.run { (n += 1) >= 4 }

    content = vcd_content(vcd)
    timestamps = content.scan(/^#(\d+)$/).flatten.map(&:to_i)

    # clk と q が変化するため複数のタイムスタンプが存在する
    assert timestamps.size >= 2
    # タイムスタンプは昇順に並んでいる
    assert_equal timestamps.sort, timestamps
  end

  # 1ビット信号は "値ID" 形式（"0x" または "1x"）で出力される
  def test_1bit_signal_value_format
    tb  = VCDBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build
    vcd = DeepSveite::VCD.new(sim)
    n = 0; sim.run { (n += 1) >= 4 }

    content = vcd_content(vcd)
    assert_match(/^[01]\S$/, content)
  end

  # 多ビット信号は "b二進数 ID" 形式で出力される
  def test_multibit_signal_value_format
    tb  = VCDBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build
    vcd = DeepSveite::VCD.new(sim)
    n = 0; sim.run { (n += 1) >= 4 }

    content = vcd_content(vcd)
    assert_match(/^b[01]+ \S$/, content)
  end

  # timescale オプションが VCD 出力に反映される
  def test_custom_timescale
    tb  = VCDBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build
    vcd = DeepSveite::VCD.new(sim, timescale: "10 ps")
    n = 0; sim.run { (n += 1) >= 2 }

    content = vcd_content(vcd)
    assert_match(/\$timescale 10 ps \$end/, content)
  end

  # time_step オプションがタイムスタンプ間隔に反映される
  def test_custom_time_step
    tb  = VCDBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build
    vcd = DeepSveite::VCD.new(sim, time_step: 5)
    n = 0; sim.run { (n += 1) >= 4 }

    content = vcd_content(vcd)
    # time_step=5 なので最初の変化は #5 に現れる
    assert_match(/^#5$/, content)
  end

  # VCD を生成しなくてもシミュレーションは正常に動作する（ゼロオーバーヘッド）
  def test_simulation_without_vcd
    tb  = VCDBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build
    # VCD を生成しない

    n = 0
    sim.run { (n += 1) >= 8 }

    # 8ステップ = 4 posedge → q = 4
    assert_equal 4, tb.counter.q.r
  end
end
