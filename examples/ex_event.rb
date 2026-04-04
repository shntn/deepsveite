require_relative "../lib/deepsveite"

class Reader < DeepSveite::Module
  attr_accessor :event_a, :event_b
  process :run

  def initialize
    @event_a = nil
    @event_b = nil
    super()
  end

  def run
    @event_a.wait
    puts "Event A triggered."
    @event_a.wait
    puts "Deferred event A triggered."
    (@event_a | @event_b).wait
    puts "event A or B triggered."
    (@event_a & @event_b).wait
    puts "event A and B triggered."
  end
end

class Writer < DeepSveite::Module
  attr_accessor :event_a, :event_b
  process :run

  def initialize
    @event_a = nil
    @event_b = nil
    super()
  end

  def run
    @event_a.notify
    puts "Event A notified."
    wait
    @event_a.notify_deferred
    puts "Deferred event A notified."
    wait
    @event_a.notify
    wait
    @event_a.notify
    wait
    @event_b.notify
  end
end

class Bench < DeepSveite::TestBench
  def initialize
    super()
    @event_a = DeepSveite::Event.new
    @event_b = DeepSveite::Event.new
    @mod_reader = Reader.new
    @mod_writer = Writer.new
    @mod_reader.event_a = @event_a.reader
    @mod_writer.event_a = @event_a.writer
    @mod_reader.event_b = @event_b.reader
    @mod_writer.event_b = @event_b.writer
  end
end

def main
  tb = Bench.new
  sim = DeepSveite::Simulator.new(tb)
  sim.build
  sim.run
end

main