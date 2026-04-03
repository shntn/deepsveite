# frozen_string_literal: true

module DeepSveite
  class FIFO
    def initialize(size: Float::INFINITY)
      @size            = size
      @pending         = []  # write されたデータ（まだ読めない）
      @ready           = []  # 読み出し可能なデータ
      @waiting_readers = []  # read 待ちの Fiber
    end

    def reader = FIFOReader.new(self)
    def writer = FIFOWriter.new(self)

    def _write(data)  = @pending << data
    def _read         = @ready.shift
    def _ready?       = @ready.any?

    def _register_waiting_reader(fiber)
      @waiting_readers << fiber
    end

    # クロック通知フェーズで呼ばれる。起床させる Fiber の配列を返す
    def _clock_tick
      @ready.concat(@pending)
      @pending.clear
      @waiting_readers.tap { @waiting_readers = [] }
    end
  end

  class FIFOReader
    def initialize(fifo)
      @fifo = fifo
    end

    def read
      unless @fifo._ready?
        @fifo._register_waiting_reader(Fiber.current)
        Fiber.yield(:fifo_wait)
      end
      @fifo._read
    end
  end

  class FIFOWriter
    def initialize(fifo)
      @fifo = fifo
    end

    def write(data)
      @fifo._write(data)
    end
  end
end
