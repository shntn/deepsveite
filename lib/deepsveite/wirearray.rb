# frozen_string_literal: true

module DeepSveite
  class WireArray
    attr_accessor :_name, :_parent

    def initialize(width: 1, size: 1)
      @_width    = width
      @_size     = size
      @_elements = Array.new(size) { Wire.new(width: width) }
      @_name     = nil
      @_parent   = nil
    end

    def [](index)
      _element(index).w
    end

    # RTL プロセス内は更新イベント経由、プロセス外（初期化 / TLM / TestBench）は即時反映
    def []=(index, value)
      elem = _element(index)
      elem.w = value
      return if DeepSveite.current_process
      DeepSveite._active_updates.delete(elem)
      DeepSveite._pending_evals.merge(elem._update)
    end

    def _input  = true
    def _output = true

    def _register_destination(process)
      @_elements.each { |elem| elem._register_destination(process) }
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
