# frozen_string_literal: true

module DeepSveite
  class ConditionDescriptor
    attr_reader :name, :edge
    def initialize(name, edge)
      @name = name # :clk
      @edge = edge # :posedge, :negedge
    end
  end
end
