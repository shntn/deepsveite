# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

class TestWire < Minitest::Test

  def test_wire
    wire = DeepSveite::Wire.new

    assert_equal wire.class, DeepSveite::Wire
    assert_equal wire.w, 0

    wire.w = 1
    assert_equal wire.w, 0

    wire._update
    assert_equal wire.w, 1
  end

  def test_wire_in
    wire = DeepSveite::Wire.new(width: 8)
    wire_in = wire.in

    wire.w = 15
    wire._update

    assert_equal wire.w, 15
    assert_equal wire_in.w, 15
  end

  def test_wire_out
    wire = DeepSveite::Wire.new(width: 4)
    wire_out = wire.out

    wire.w = 7
    wire._update
    assert_equal wire.w, 7

    wire_out.w = 15
    wire._update
    assert_equal wire.w, 15
  end

  def test_wire_raise
    wire = DeepSveite::Wire.new(width: 8)
    wire_in = wire.in
    wire_out = wire.out

    assert_raises(RuntimeError) { wire_in.w = 15 }
    # TODO :
    # ビットセレクト、パートセレクトによる更新ができないため、
    # 暫定処置として読み出しを許可
    #assert_raises(RuntimeError) { wire_out.w }
  end
end