# frozen_string_literal: true

module DeepSveite
  class Event
    attr_accessor :_sim, :_parent, :_name

    def initialize
      @_sim     = nil
      @_parent  = nil
      @_name    = nil
      @_waiting = []
      @_latches = []
      @_fired   = false
    end

    def reader = EventReader.new(self)
    def writer = EventWriter.new(self)

    def _register_waiting(fiber)
      @_waiting << fiber
    end

    def _register_latch(latch)
      @_latches << latch
    end

    def _unregister_latch(latch)
      @_latches.delete(latch)
    end

    def _vcd_probe
      VCDProbe.new(
        name:   @_name,
        parent: @_parent,
        width:  1,
        reset:  -> { @_fired = false }
      ) { @_fired ? 1 : 0 }
    end

    # 即時通知: 同一 TLM デルタサイクルで待機 Fiber を起床
    def _notify
      @_fired = true
      fibers  = @_waiting.dup
      latches = @_latches.dup
      @_waiting.clear
      @_latches.clear
      @_sim._tlm_notify_immediate(fibers)
      latches.each { |latch| latch.fire_immediate(@_sim) }
    end

    # 遅延通知: 次のクロック通知フェーズで待機 Fiber を起床
    def _notify_deferred
      @_fired = true
      fibers  = @_waiting.dup
      latches = @_latches.dup
      @_waiting.clear
      @_latches.clear
      @_sim._tlm_notify_deferred(fibers)
      latches.each { |latch| latch.fire_deferred(@_sim) }
    end
  end

  # OR ラッチ: 最初に発火したイベントで Fiber を起床し、残りのイベントから自身を削除
  class OnceLatch
    def initialize(fiber, events)
      @fiber  = fiber
      @fired  = false
      @events = events
    end

    def fire_immediate(sim)
      return if @fired
      @fired = true
      _cancel_others
      sim._tlm_notify_immediate([@fiber])
    end

    def fire_deferred(sim)
      return if @fired
      @fired = true
      _cancel_others
      sim._tlm_notify_deferred([@fiber])
    end

    private

    def _cancel_others
      @events.each { |ev| ev._unregister_latch(self) }
    end
  end

  # AND ラッチ: 全イベントが発火したときに Fiber を起床
  class CountLatch
    def initialize(fiber, events)
      @fiber  = fiber
      @total  = events.size
      @count  = 0
      @fired  = false
    end

    def fire_immediate(sim)
      return if @fired
      @count += 1
      return unless @count >= @total
      @fired = true
      sim._tlm_notify_immediate([@fiber])
    end

    def fire_deferred(sim)
      return if @fired
      @count += 1
      return unless @count >= @total
      @fired = true
      sim._tlm_notify_deferred([@fiber])
    end
  end

  class EventReader
    def _event = @event

    def initialize(event)
      @event = event
    end

    def wait
      @event._register_waiting(Fiber.current)
      Fiber.yield(:event_wait)
    end

    def |(other)
      EventOrReader.new([self, other])
    end

    def &(other)
      EventAndReader.new([self, other])
    end
  end

  class EventOrReader
    def initialize(readers)
      @readers = readers
    end

    def |(other)
      EventOrReader.new(@readers + [other])
    end

    def wait
      events = @readers.map(&:_event)
      latch  = OnceLatch.new(Fiber.current, events)
      events.each { |ev| ev._register_latch(latch) }
      Fiber.yield(:event_wait)
    end
  end

  class EventAndReader
    def initialize(readers)
      @readers = readers
    end

    def &(other)
      EventAndReader.new(@readers + [other])
    end

    def wait
      events = @readers.map(&:_event)
      latch  = CountLatch.new(Fiber.current, events)
      events.each { |ev| ev._register_latch(latch) }
      Fiber.yield(:event_wait)
    end
  end

  class EventWriter
    def initialize(event)
      @event = event
    end

    def notify          = @event._notify
    def notify_deferred = @event._notify_deferred
  end
end
