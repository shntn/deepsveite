# frozen_string_literal: true

module DeepSveite
  class Simulator
    def initialize(test_bench, clock = nil)
      @tb = test_bench
      @eb = DeepSveite::EnvironmentBuilder.new
      @_clock = clock || DeepSveite::Wire.new
      @_pre_active_collections = []
      @_reg_conditions = {}
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

    def register_reg_condition(reg, edge:, method:)
      @_reg_conditions[reg] ||= []
      @_reg_conditions[reg] << { edge: edge, method: method }
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
      @_reg_conditions.each do |reg, conditions|
        edge = if reg.posedge
                 :posedge
               elsif reg.negedge
                 :negedge
               else
                 nil
               end
        conditions.each do |cond|
          @_rtl_eval_queue << cond[:method] if cond[:edge].nil? || cond[:edge] == edge
        end
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