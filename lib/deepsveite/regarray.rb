# frozen_string_literal: true

module DeepSveite
  class RegArray
    attr_accessor :_name, :_parent

    def initialize(width: 1, size: 1)
      @_width    = width
      @_size     = size
      @_data     = Array.new(size, 0)   # 即時読み書き用（TLM/RTL 共通）
      @_elements = Array.new(size) { Reg.new(width: width) }  # VCD 出力用
      @_name     = nil
      @_parent   = nil
    end

    # 即時読み出し（TLM / RTL 両対応）
    def [](index)
      @_data[index]
    end

    # 即時書き込み + Reg 要素に NBA スケジュール（VCD 同期用）
    def []=(index, value)
      @_data[index] = value
      @_elements[index].r = value
    end

    def _elements = @_elements
  end
end
