# frozen_string_literal: true

module DeepSveite
  class Simulator
    def initialize(test_bench)
      @tb = test_bench
      @eb = DeepSveite::EnvironmentBuilder.new
      @_wires = []
      @ready_queue_wires = []
    end

    def build
      @eb.build(self, @tb)
      update
    end

    def register_wire(wire)
      @_wires << wire
    end

    def run; end

    def step
      _rtl_cycle
    end

    def _rtl_cycle
      while true
        @ready_queue_wires.each do |method|
          method.call
        end
        @ready_queue_wires.clear
        update
        break unless @ready_queue_wires.any?
      end
    end

    def update
      @_wires.each do |wire|
        methods = wire._update
        @ready_queue_wires |= methods
      end
    end
  end
end