# frozen_string_literal: true

module DeepSveite
  class Signal
    def initialize; end

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
