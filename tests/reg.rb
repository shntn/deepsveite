# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

class TestReg < Minitest::Test

  # 初期値は 0
  def test_initial_value
    reg = DeepSveite::Reg.new
    assert_equal 0, reg.r
  end

  # r= はノンブロッキング代入: _update を呼ぶまで値は確定しない
  def test_write_is_non_blocking
    reg = DeepSveite::Reg.new
    reg.r = 5
    assert_equal 0, reg.r
  end

  # _update を呼ぶと書き込みが確定する
  def test_update_commits_write
    reg = DeepSveite::Reg.new
    reg.r = 5
    reg._update
    assert_equal 5, reg.r
  end

  # .in ポートは読み出し専用: r= すると例外になる
  def test_in_port_is_read_only
    reg     = DeepSveite::Reg.new
    reg_in  = reg.in
    assert_raises(RuntimeError) { reg_in.r = 5 }
  end

  # .out ポート経由で書き込んだ値は元の Reg に反映される
  def test_out_port_writes_to_content
    reg     = DeepSveite::Reg.new(width: 8)
    reg_out = reg.out
    reg_out.r = 7
    reg._update
    assert_equal 7, reg.r
  end

  # 0 → 非ゼロ の変化で posedge が true になる
  def test_posedge
    reg = DeepSveite::Reg.new
    reg.r = 1
    reg._update
    assert reg.posedge
  end

  # 非ゼロ → 0 の変化で negedge が true になる
  def test_negedge
    reg = DeepSveite::Reg.new
    reg.r = 1
    reg._update
    reg.r = 0
    reg._update
    assert reg.negedge
  end

  # 同じ値が続く場合は posedge / negedge ともに false
  def test_no_edge_without_change
    reg = DeepSveite::Reg.new
    reg.r = 1
    reg._update

    reg.r = 1  # 値は変わらない
    reg._update

    refute reg.posedge
    refute reg.negedge
  end
end
