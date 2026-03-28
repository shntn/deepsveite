# frozen_string_literal: true

module DeepSveite
  class Simulator
    def initialize(test_bench, clock = nil)
      @tb = test_bench
      @eb = DeepSveite::EnvironmentBuilder.new
      @_clock = clock || DeepSveite::Wire.new
      @_wires = []
      @_regs = []
      @_testbench_signals = []
      @_reg_conditions = {}
      @ready_queue_regs = []
      @ready_queue_wires = []
    end

    def build
      @eb.build(self, @tb)
      _rtl_update
      _clock_update
    end

    def register_reg(reg)
      @_regs << reg
    end

    def register_reg_condition(reg, edge:, method:)
      @_reg_conditions[reg] ||= []
      @_reg_conditions[reg] << { edge: edge, method: method }
    end

    def register_wire(wire)
      @_wires << wire
    end

    def register_testbench_signal(wire)
      @_testbench_signals << wire
    end

    def run(&halt_condition)
      loop do
        step
        break if halt_condition.call
      end
    end

    def step
      @_clock.w = @_clock.w == 1 ? 0 : 1
      _testbench_update
      _evaluate_conditions
      _rtl_cycle
      _clock_update
    end

    def _rtl_cycle
      while true
        @ready_queue_regs.each  { |method| method.call }
        @ready_queue_wires.each { |method| method.call }
        _rtl_update
        break unless @ready_queue_regs.any? || @ready_queue_wires.any?
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
          @ready_queue_regs << cond[:method] if cond[:edge].nil? || cond[:edge] == edge
        end
      end
    end

    def _rtl_update
      @ready_queue_regs.clear
      @ready_queue_wires.clear
      update_combinational
    end

    def _clock_update
      @ready_queue_regs.clear
      update_sequential
    end

    def update_sequential
      @_regs.each do |reg|
        methods = reg._update
        @ready_queue_regs |= methods
      end
    end

    def update_combinational
      @_wires.each do |wire|
        methods = wire._update
        @ready_queue_wires |= methods
      end
    end

    def _testbench_update
      @_testbench_signals.each do |signal|
        methods = signal._update
        if signal.is_a?(DeepSveite::Wire)
          @ready_queue_wires |= methods
        elsif signal.is_a?(DeepSveite::Reg)
          @ready_queue_regs |= methods
        end
      end
    end
  end
end