# frozen_string_literal: true

module DeepSveite
  class Simulator
    def initialize(test_bench, clock = nil)
      @tb = test_bench
      @eb = DeepSveite::EnvironmentBuilder.new
      @_clock = clock || DeepSveite::Wire.new
      @_wires = []
      @_regs = []
      @_reg_conditions = {}
      @ready_queue_regs = []
      @ready_queue_wires = []
    end

    def build
      @eb.build(self, @tb)
      update
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

    def run(&halt_condition)
      loop do
        step
        break if halt_condition.call
      end
    end

    def step
      @_clock.w = @_clock.w == 1 ? 0 : 1
      _rtl_cycle
    end

    def _rtl_cycle
      while true
        @ready_queue_regs.each  { |method| method.call }
        @ready_queue_wires.each { |method| method.call }
        update
        break unless @ready_queue_regs.any? || @ready_queue_wires.any?
      end
    end

    def _evaluate_conditions
      @_reg_conditions.each do |reg, conditions|
        edge = reg.posedge ? :posedge : reg.negedge ? :negedge : nil
        conditions.each do |cond|
          @ready_queue_regs << cond[:method] if cond[:edge].nil? || cond[:edge] == edge
        end
      end
    end

    def update
      @ready_queue_regs.clear
      @ready_queue_wires.clear
      update_sequential
      update_combinational
      _evaluate_conditions
    end

    def update_sequential
      @_regs.each(&:_update)
    end

    def update_combinational
      @_wires.each do |wire|
        methods = wire._update
        @ready_queue_wires |= methods
      end
    end
  end
end