require_relative "../lib/deepsveite"

DS = DeepSveite

# TLM VCD サンプル: FIFO と Event の波形記録
#
# Producer が毎サイクル FIFO に値を書き込み、Consumer が読み出す。
# FIFO の各スロット（data_fifo[0]〜[4]）と
# Event のパルス（ev_produced, ev_consumed）が VCD に記録される。

class Producer < DS::Module
  attr_accessor :fifo_writer, :event_produced
  process :run

  def initialize
    super()
  end

  def run
    # 1サイクルで5アイテムをまとめて書き込む
    5.times do |i|
      @fifo_writer.write((i + 1) * 10)
    end
    @event_produced.notify
    wait
    # さらに3アイテム追加
    3.times do |i|
      @fifo_writer.write((i + 6) * 10)
    end
    @event_produced.notify
  end
end

class Consumer < DS::Module
  attr_accessor :fifo_reader, :event_consumed
  process :run

  def initialize
    super()
  end

  def run
    8.times do
      val = @fifo_reader.read
      puts "consumed: #{val}"
      @event_consumed.notify
      wait
    end
  end
end

class Bench < DS::TestBench
  def initialize
    super()
    @data_fifo   = DS::FIFO.new(size: 5, width: 8)
    @ev_produced = DS::Event.new
    @ev_consumed = DS::Event.new

    @producer = Producer.new
    @consumer = Consumer.new

    @producer.fifo_writer    = @data_fifo.writer
    @producer.event_produced = @ev_produced.writer
    @consumer.fifo_reader    = @data_fifo.reader
    @consumer.event_consumed = @ev_consumed.writer
  end
end

def main
  tb  = Bench.new
  sim = DS::Simulator.new(tb)
  sim.build

  vcd = DS::VCD.new(sim, filename: "examples/tlm_signals.vcd")

  sim.run

  vcd.write
  puts "VCD を examples/tlm_signals.vcd に出力しました。"
end

main
