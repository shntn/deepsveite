# frozen_string_literal: true

module DeepSveite
  class RegArray
    attr_accessor :_name, :_parent

    def initialize(width: 1, size: 1)
      @_width    = width
      @_size     = size
      @_elements = Array.new(size) { Reg.new(width: width) }
      @_name     = nil
      @_parent   = nil
    end

    def [](index)
      _element(index).r
    end

    # RTL プロセス内は NBA、プロセス外（TLM / TestBench）は即時反映
    def []=(index, value)
      elem = _element(index)
      elem.r = value
      return if DeepSveite.current_process
      DeepSveite._nba_updates.delete(elem)
      elem._update
    end

    def _elements = @_elements

    private

    def _element(index)
      unless index.is_a?(Integer) && index.between?(0, @_size - 1)
        raise IndexError, "index #{index} out of range (size #{@_size}) in #{@_name || self.class}"
      end
      @_elements[index]
    end
  end
end
