# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

# テスト用モジュール: a と b を加算して result に書き込む組み合わせ回路
class Adder < DeepSveite::Module
  always_comb :add, reads: [:a, :b], writes: [:result]

  def initialize(a, b, result)
    @a      = a.in
    @b      = b.in
    @result = result.out
    super()
  end

  def add
    @result.w = @a.w + @b.w
  end
end

class Bench < DeepSveite::TestBench
  attr_accessor :a, :b, :result, :adder

  def initialize
    super()
    @a      = DeepSveite::Wire.new(width: 8)
    @b      = DeepSveite::Wire.new(width: 8)
    @result = DeepSveite::Wire.new(width: 8)
    @adder  = Adder.new(@a, @b, @result)
  end
end

class TestModule < Minitest::Test
  def test_module_is_subclass
    assert_kind_of DeepSveite::Module, Class.new(DeepSveite::Module).new
  end

  # always_comb の DSL 宣言が正しく記録されているかを確認
  def test_always_comb_declaration
    decl = Adder._pending_combinational.first
    assert_equal :add,       decl[:method]
    assert_equal [:a, :b],   decl[:reads]
    assert_equal [:result],  decl[:writes]
  end

  # 入力ワイヤーを変化させて step すると、組み合わせロジックが実行される
  def test_step_triggers_combinational
    tb    = Bench.new
    sim   = DeepSveite::Simulator.new(tb)
    sim.build

    tb.a.w = 3
    tb.b.w = 4
    sim.step

    assert_equal 7, tb.result.w
  end

  # step を呼ぶ前は出力に反映されない
  def test_output_unchanged_before_step
    tb    = Bench.new
    sim   = DeepSveite::Simulator.new(tb)
    sim.build

    tb.a.w = 3
    tb.b.w = 4

    assert_equal 0, tb.result.w
  end

  # reads: に指定したワイヤーのみがコールバックをトリガーする。
  # writes: に指定したワイヤーを直接変化させても add は発火しない。
  def test_only_reads_trigger_callback
    tb    = Bench.new
    sim   = DeepSveite::Simulator.new(tb)
    sim.build

    tb.a.w = 3
    tb.b.w = 4
    sim.step

    assert_equal 7, tb.result.w

    # writes: のワイヤーを直接変更しても add は発火しない
    tb.result.w = 99
    sim.step
    assert_equal 99, tb.result.w

    # reads: のワイヤーを変更すると add が発火して result が上書きされる
    tb.a.w = 5
    sim.step
    assert_equal 9, tb.result.w  # 5 + 4

    # reads: のワイヤーを変更すると add が発火して result が上書きされる
    tb.b.w = 6
    sim.step
    assert_equal 11, tb.result.w
  end
end
