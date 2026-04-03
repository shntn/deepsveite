require_relative "../lib/deepsveite"

DS = DeepSveite

class Reader < DeepSveite::Module
  attr_accessor :reader_fifo
  process :run

  def initialize
    @reader_fifo = nil
    super()
  end

  def run
    5.times do
      i = @reader_fifo.read
      puts "read #{i}"
    end
  end

end

class Writer < DeepSveite::Module
  attr_accessor :writer_fifo
  process :run

  def initialize
    @writer_fifo = nil
    super()
  end

  def run
    5.times do |i|
      @writer_fifo.write(i)
      puts "write #{i}"
    end
  end
end

class Bench < DS::TestBench
  def initialize
    super()
    @fifo = DeepSveite::FIFO.new(size: 5)
    @mod_reader = Reader.new
    @mod_writer = Writer.new
    @mod_reader.reader_fifo = @fifo.reader
    @mod_writer.writer_fifo = @fifo.writer
  end
end

def main
  tb = Bench.new
  sim = DeepSveite::Simulator.new(tb)
  sim.build
  sim.run
end

main