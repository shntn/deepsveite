# frozen_string_literal: true

module DeepSveite
  class Module
    attr_accessor :_name, :_parent

    def initialize
      @_name = nil
      @_parent = nil
    end

    def self.always_ff(method_name, cond: [], reads: nil, writes: nil)
      @_sequential ||= []
      @_sequential << { method: method_name, cond: cond, reads: reads, writes: writes }
    end

    def self.always_comb(method_name, reads: nil, writes: nil)
      @_combinational ||= []
      @_combinational << { method: method_name, reads: reads, writes: writes }
    end

    def self.process(method_name)
      @_process ||= []
      @_process << { method: method_name }
    end

    def self._pending_sequential
      @_sequential || []
    end

    def self._pending_combinational
      @_combinational || []
    end

    def self._pending_process
      @_process || []
    end

    def self.vcd_signal(name, width:, size: nil)
      @_vcd_signals ||= []
      @_vcd_signals << { name: name, width: width, size: size }
    end

    def self._pending_vcd_signals
      @_vcd_signals || []
    end

    def wait
      Fiber.yield(:next_cycle)
    end
  end
end
