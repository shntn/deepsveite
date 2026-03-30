# frozen_string_literal: true

module DeepSveite
  class Simulator
    def initialize(test_bench, clock = nil)
      @tb = test_bench
      @eb = DeepSveite::EnvironmentBuilder.new
      @_clock = clock || DeepSveite::Wire.new
      @_pre_active_collections = []
      @_rtl_conditions = []
      @_rtl_collections = []
      @_rtl_eval_queue = []
    end

    def build
      @eb.build(self, @tb)
      _rtl_update
    end

    def register_pre_active_collections(signals)
      @_pre_active_collections |= signals
    end

    def register_rtl_condition(edge_trigger)
      @_rtl_conditions ||= []
      @_rtl_conditions << edge_trigger
    end

    def register_rtl_collections(signal)
      @_rtl_collections << signal
    end

    def run(&halt_condition)
      loop do
        step
        break if halt_condition.call
      end
    end

    def step
      @_clock.w = @_clock.w == 1 ? 0 : 1
      _update_pre_active
      _rtl_cycle
    end

    def _rtl_cycle
      _evaluate_conditions
      while true
        @_rtl_eval_queue.each  { |method| method.call }
        _rtl_update
        _update_pre_active
        break unless @_rtl_eval_queue.any?
      end
    end

    def _evaluate_conditions
      @_rtl_conditions.each do |trigger|
        @_rtl_eval_queue << trigger.method if trigger.met?
      end
    end

    def _rtl_update
      @_rtl_eval_queue.clear
      @_rtl_collections.each do |signal|
        methods = signal._update
        @_rtl_eval_queue |= methods
      end
    end

    def _update_pre_active
      @_pre_active_collections.each do |signal|
        methods = signal._update
        @_rtl_eval_queue |= methods
      end
    end
  end
end