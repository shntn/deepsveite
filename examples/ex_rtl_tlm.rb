require_relative "../lib/deepsveite"

DS = DeepSveite

# =============================================================================
# Demo 1: TLM → RTL
# TLM の Processor が Wire 経由で RTL の Accumulator に加算命令を送る
#
# TLM から Wire を操作する際のタイミング:
#   1. Wire に値をセット（_pending に書き込み）
#   2. wait x 1: TLM は negedge で動作するため、次の posedge で RTL が取り込み、
#                NBA まで完了した後に TLM が再起動する
#   3. Reg 値を読み出す（wait 復帰時には NBA 反映済み）
# =============================================================================

class Accumulator < DS::Module
  attr_accessor :clk, :data_in, :add_en
  always_ff :add, cond: [:clk.posedge]

  def initialize
    @result = DS::Reg.new(width: 16)
    super()
  end

  def result = @result

  def add
    @result.r = @result.r + @data_in.w if @add_en.w == 1
  end
end

class Processor < DS::Module
  attr_accessor :data_in, :add_en, :acc
  process :run

  def run
    [10, 20, 30].each do |val|
      @data_in.w = val
      @add_en.w  = 1
      wait            # 1 RTL クロックサイクル: posedge で取り込み + NBA 完了まで待機
      puts "Processor: added #{val.to_s.rjust(2)},  result = #{@acc.result.r}"
      @add_en.w  = 0
    end
  end
end

class AccBench < DS::TestBench
  attr_accessor :clk

  def initialize
    super()
    @clk     = DS::Wire.new
    @data_in = DS::Wire.new(width: 16)
    @add_en  = DS::Wire.new

    @acc       = Accumulator.new
    @processor = Processor.new

    @acc.clk      = @clk.in
    @acc.data_in  = @data_in.in
    @acc.add_en   = @add_en.in

    @processor.data_in = @data_in
    @processor.add_en  = @add_en
    @processor.acc     = @acc
  end
end

# =============================================================================
# Demo 2: RTL → TLM
# TLM の Monitor が RTL の Counter の出力 Reg を毎クロック読み取る
#
# RTL の Reg は posedge の _clock_notification_phase (NBA) で値が確定する。
# TLM は posedge 後の negedge で動作するため、wait 後には NBA 反映済みの値を読める。
# wait x 1 = 1 RTL クロックサイクル。
# =============================================================================

class BinaryCounter < DS::Module
  attr_accessor :clk
  always_ff :tick, cond: [:clk.posedge]

  def initialize
    @count = DS::Reg.new(width: 8)
    super()
  end

  def count = @count

  def tick
    @count.r = @count.r + 1
  end
end

class CountMonitor < DS::Module
  attr_accessor :counter
  process :watch

  def watch
    loop do
      val = @counter.count.r
      puts "Monitor:   count = #{val}"
      break if val >= 5
      wait            # 次の RTL クロックサイクルへ
    end
  end
end

class CountBench < DS::TestBench
  attr_accessor :clk

  def initialize
    super()
    @clk     = DS::Wire.new
    @counter = BinaryCounter.new
    @monitor = CountMonitor.new

    @counter.clk     = @clk.in
    @monitor.counter = @counter
  end
end

def demo_tlm_to_rtl
  puts "=== Demo 1: TLM → RTL  (Wire 経由で RTL モジュールへ書き込み) ==="
  tb  = AccBench.new
  sim = DS::Simulator.new(tb, tb.clk)
  sim.build

  n = 0
  sim.run { (n += 1) >= 15 }
  puts
end

def demo_rtl_to_tlm
  puts "=== Demo 2: RTL → TLM  (RTL の出力 Reg を TLM が監視) ==="
  tb  = CountBench.new
  sim = DS::Simulator.new(tb, tb.clk)
  sim.build

  n = 0
  sim.run { (n += 1) >= 15 }
  puts
end

demo_tlm_to_rtl
demo_rtl_to_tlm
