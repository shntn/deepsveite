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
      elem = @_elements[index]
      elem ? elem.w : 0
    end

    # RTL プロセス内は更新イベント経由、プロセス外（初期化 / TLM / TestBench）は即時反映
    def []=(index, value)
      elem = @_elements.fetch(index)
      elem.w = value
      return if DeepSveite.current_process
      DeepSveite._active_updates.delete(elem)
      elem._update
    end

    def _elements = @_elements
  end
end
