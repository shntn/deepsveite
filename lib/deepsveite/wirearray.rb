# frozen_string_literal: true

module DeepSveite
  class WireArray
    attr_accessor :_name, :_parent

    def initialize(width: 1, size: 1)
      @_width    = width
      @_size     = size
      @_data     = Array.new(size, 0)   # 即時読み書き用
      @_elements = Array.new(size) { Wire.new(width: width) }  # VCD 出力用
      @_name     = nil
      @_parent   = nil
    end

    # 即時読み出し
    def [](index)
      @_data[index]
    end

    # 即時書き込み + Wire 要素に反映（VCD 同期用）
    def []=(index, value)
      @_data[index] = value
      @_elements[index].w = value
    end

    def _elements = @_elements
  end
end
