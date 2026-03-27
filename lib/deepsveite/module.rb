# frozen_string_literal: true

module DeepSveite
  class Module
    attr_accessor :_name, :_parent

    def initialize
      @_name = nil
      @_parent = nil
    end

    def self.always_ff(method_name)
      @_sequential ||= []
      @_sequential << method_name.to_sym
    end

    def self.always_comb(method_name, reads: [], writes: [])
      @_combinational ||= []
      @_combinational << { method: method_name, reads: reads, writes: writes }
    end

    def self._pending_combinational
      @_combinational || []
    end
  end
end
