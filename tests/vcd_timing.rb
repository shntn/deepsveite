# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/deepsveite"

# Reg → 組み合わせ回路2段
class VcdRegToComb < DeepSveite::Module
  attr_accessor :clk
  attr_reader :count, :double, :quad
  always_ff :tick, cond: [:clk.posedge]
  always_comb :calc_double, reads: [:count]
  always_comb :calc_quad,   reads: [:double]

  def initialize
    @count  = DeepSveite::Reg.new(width: 8)
    @double = DeepSveite::Wire.new(width: 8)
    @quad   = DeepSveite::Wire.new(width: 8)
    super()
  end

  def tick        = @count.r = @count.r + 1
  def calc_double = @double.w = @count.r * 2
  def calc_quad   = @quad.w = @double.w * 2
end

class VcdRegToCombBench < DeepSveite::TestBench
  attr_reader :clk, :dut

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @dut = VcdRegToComb.new
    @dut.clk = @clk.in
  end
end

# TestBench の 4 ビット Wire だけを持つ構成
class VcdNarrowBench < DeepSveite::TestBench
  attr_reader :clk, :w

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @w   = DeepSveite::Wire.new(width: 4)
  end
end

class TestVcdTiming < Minitest::Test

  # VCD ファイルを { 時刻 => { 信号名 => 値 } } に読み込む
  def parse_changes(vcd)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.vcd")
      vcd.write(path)
      ids     = {}
      changes = Hash.new { |hash, time| hash[time] = {} }
      time    = nil
      File.readlines(path).each do |raw|
        line = raw.strip
        case line
        when /\A\$var \w+ \d+ (\S+) (\S+) \$end\z/ then ids[$1] = $2
        when /\A#(\d+)\z/                            then time = $1.to_i
        when /\Ab([01]+) (\S+)\z/                    then changes[time][ids[$2]] = $1.to_i(2) if time
        when /\A([01])(\S+)\z/                       then changes[time][ids[$2]] = $1.to_i if time
        end
      end
      changes
    end
  end

  # Reg の更新に反応する組み合わせ出力は、Reg と同じ時刻に記録される
  def test_comb_output_changes_at_same_time_as_reg
    tb  = VcdRegToCombBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build
    vcd = DeepSveite::VCD.new(sim)

    sim.step  # step_count = 1 → time 10（posedge）
    sim.step  # time 20（negedge）: 変化なし
    sim.step  # time 30（posedge）

    changes = parse_changes(vcd)
    assert_equal({ "count" => 1, "double" => 2, "quad" => 4 }, changes[10].slice("count", "double", "quad"))
    refute_includes changes[20].keys, "count"
    assert_equal({ "count" => 2, "double" => 4, "quad" => 8 }, changes[30].slice("count", "double", "quad"))
  end

  # 幅でマスクされて値が変わらない書き込みは、VCD に変化として記録されない
  def test_masked_write_without_change_is_not_recorded
    tb  = VcdNarrowBench.new
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build
    vcd = DeepSveite::VCD.new(sim)

    tb.w.w = 0x10  # 4 ビットにマスクされて 0 のまま
    sim.step       # time 10
    tb.w.w = 0x13  # 3 になる
    sim.step       # time 20

    changes = parse_changes(vcd)
    refute_includes changes[10].keys, "w"
    assert_equal 3, changes[20]["w"]
  end
end
