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
    assert_raises(RuntimeError) { wire_out.w }
  end

  # 幅を超える値は幅でマスクされる
  def test_wire_masks_value_to_width
    wire = DeepSveite::Wire.new(width: 8)
    wire.w = 0x1FF
    wire._update
    assert_equal 0xFF, wire.w

    wire.w = 255 + 1
    wire._update
    assert_equal 0, wire.w
  end

  # 負数は 2 の補数で保持される
  def test_wire_masks_negative_value
    wire = DeepSveite::Wire.new(width: 8)
    wire.w = -1
    wire._update
    assert_equal 0xFF, wire.w
  end

  # true / false は 1 / 0 になる
  def test_wire_converts_boolean
    wire = DeepSveite::Wire.new
    wire.w = true
    wire._update
    assert_equal 1, wire.w

    wire.w = false
    wire._update
    assert_equal 0, wire.w
  end

  # ビット・範囲書き込みも幅を超えない
  def test_wire_masks_bit_and_range_write
    wire = DeepSveite::Wire.new(width: 4)
    wire[7] = 1
    wire[0..7] = 0xFF
    wire._update
    assert_equal 0xF, wire.w
  end

  # 初期値も幅でマスクされる
  def test_wire_masks_init
    wire = DeepSveite::Wire.new(init: 0x1F, width: 4)
    wire._update
    assert_equal 0xF, wire.w
  end
end
