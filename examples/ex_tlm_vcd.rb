require_relative "../lib/deepsveite"

DS = DeepSveite

# TLM VCD サンプル: FIFO / Event / vcd_signal の波形記録
#
# Producer が毎サイクル FIFO に値を書き込み、Consumer が読み出す。
# - FIFO の各スロット（data_fifo[0]〜[4]）
# - Event のパルス（ev_produced, ev_consumed）
# - Producer の内部カウンタ（vcd_signal スカラー）
# - Consumer の受信ログ配列（vcd_signal 配列）
# が VCD に記録される。

class Producer < DS::Module
  attr_accessor :fifo_writer, :event_produced

  vcd_signal :total_sent, width: 8   # 送信済み合計（スカラー）

  process :run

  def initialize
    @total_sent = 0
    super()
  end

  def run
    5.times do |i|
      @fifo_writer.write((i + 1) * 10)
      @total_sent += 1
    end
    @event_produced.notify
    wait
    3.times do |i|
      @fifo_writer.write((i + 6) * 10)
      @total_sent += 1
    end
    @event_produced.notify
  end
end

class Consumer < DS::Module
  attr_accessor :fifo_reader, :event_consumed

  vcd_signal :last_received, width: 8          # 直近の受信値（スカラー）
  vcd_signal :log,           width: 8, size: 8 # 受信ログ配列

  process :run

  def initialize
    @last_received = 0
    @log = Array.new(8, 0)
    @log_idx = 0
    super()
  end

  def run
    8.times do
      val = @fifo_reader.read
      puts "consumed: #{val}"
      @last_received     = val
      @log[@log_idx % 8] = val
      @log_idx += 1
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
