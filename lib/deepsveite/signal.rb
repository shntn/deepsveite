# frozen_string_literal: true

module DeepSveite
  class Signal
    def initialize; end

    # 書き込み値を幅でマスクする。true/false は 1/0、整数以外はそのまま通す
    def _mask(value)
      value = 1 if value == true
      value = 0 if value == false
      return value unless value.is_a?(Integer)
      value & ((1 << @_width) - 1)
    end

    def _register_edge_destination(edge, process)
      if self == @_content
        @_edge_destinations << [edge, process]
      else
        @_content._register_edge_destination(edge, process)
      end
    end

    # 値が変化した更新イベントに対して起動するエッジ感度プロセス
    def _edge_methods
      return [] if @_old.nil?
      @_edge_destinations.filter_map { |edge, process| process if send(edge) }
    end
  end
end
