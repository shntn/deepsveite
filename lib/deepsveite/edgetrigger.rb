# frozen_string_literal: true

module DeepSveite
  class EdgeTrigger
    attr_reader :method
    def initialize(signal, edge, method)
      @signal = signal
      @edge = edge
      @method = method
    end

    def met?
      case @edge
      when :posedge then @signal.posedge
      when :negedge then @signal.negedge
      else false
      end
    end
  end
end