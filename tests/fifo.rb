# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

# -----------------------------------------------------------------------
# 共通モジュール
# -----------------------------------------------------------------------

class FIFOProducer < DeepSveite::Module
  attr_accessor :fifo
  attr_reader   :log

  def initialize(values)
    @values = values
    @log    = []
    super()
  end

  process :run
  def run
    @values.each do |v|
      @fifo.write(v)
      @log << v
    end
  end
end

class FIFOConsumer < DeepSveite::Module
  attr_accessor :fifo
  attr_reader   :log

  def initialize(count)
    @count = count
    @log   = []
    super()
  end

  process :run
  def run
    @count.times do
      @log << @fifo.read
    end
  end
end

class FIFOBench < DeepSveite::TestBench
  attr_reader :fifo, :producer, :consumer

  def initialize(values, read_count = values.size)
    super()
    @fifo     = DeepSveite::FIFO.new
    @producer = FIFOProducer.new(values)
    @consumer = FIFOConsumer.new(read_count)
    @producer.fifo = @fifo.writer
    @consumer.fifo = @fifo.reader
  end
end

# RTL クロック付きの協調シミュレーション用ベンチ
class FIFOClockBench < DeepSveite::TestBench
  attr_reader :clk, :producer, :consumer

  def initialize(values)
    super()
    @clk      = DeepSveite::Wire.new
    @fifo     = DeepSveite::FIFO.new
    @producer = FIFOProducer.new(values)
    @consumer = FIFOConsumer.new(values.size)
    @producer.fifo = @fifo.writer
    @consumer.fifo = @fifo.reader
  end
end

# -----------------------------------------------------------------------

class TestFIFO < Minitest::Test

  # write したデータを read で取り出せる
  def test_write_and_read
    tb  = FIFOBench.new([42])
    sim = DeepSveite::Simulator.new(tb)
    sim.build
    sim.run

    assert_equal [42], tb.consumer.log
  end

  # write したデータは FIFO 順（先入れ先出し）で取り出せる
  def test_fifo_order
    tb  = FIFOBench.new([10, 20, 30])
    sim = DeepSveite::Simulator.new(tb)
    sim.build
    sim.run

    assert_equal [10, 20, 30], tb.consumer.log
  end

  # write したデータは同クロックでは read できない（1クロック遅延）
  # → Consumer が先に起動して read を呼んでも、Producer が write するまでブロックする
  def test_read_blocks_until_next_clock
    # Consumer を先に起動させるために Consumer だけの Bench を用意し、
    # あとから Producer を加えることで「Consumer が先に read を呼ぶ」状況を作る
    tb  = FIFOBench.new([99])
    sim = DeepSveite::Simulator.new(tb)
    sim.build
    sim.run

    # read がブロックせずすり抜けていれば log は空のまま（バグ）
    # 正しくは 99 が入っている
    assert_equal [99], tb.consumer.log
  end

  # 複数の値を write → 同数を read できる
  def test_multiple_values
    values = [1, 2, 3, 4, 5]
    tb     = FIFOBench.new(values)
    sim    = DeepSveite::Simulator.new(tb)
    sim.build
    sim.run

    assert_equal values, tb.consumer.log
  end

  # write した件数より少ない read を指定した場合、指定した件数だけ取り出せる
  def test_partial_read
    tb  = FIFOBench.new([10, 20, 30, 40, 50], 3)
    sim = DeepSveite::Simulator.new(tb)
    sim.build
    sim.run

    assert_equal [10, 20, 30], tb.consumer.log
  end

  # RTL クロック付き協調シミュレーションでも動作する
  # write は negedge で行われ、posedge で ready に移動し、次の negedge で read できる
  def test_with_rtl_clock
    tb  = FIFOClockBench.new([7, 8, 9])
    sim = DeepSveite::Simulator.new(tb, tb.clk)
    sim.build

    n = 0
    sim.run { (n += 1) >= 20 }

    assert_equal [7, 8, 9], tb.consumer.log
  end
end
