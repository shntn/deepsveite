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

    def self._pending_sequential
      @_sequential || []
    end

    def self._pending_combinational
      @_combinational || []
    end
  end
end
