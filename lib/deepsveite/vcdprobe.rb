# frozen_string_literal: true

module DeepSveite
  class VCDProbe
    attr_accessor :_name, :_parent, :_width

    def initialize(name:, parent:, width:, reset: nil, &value_proc)
      @_name       = name
      @_parent     = parent
      @_width      = width
      @_value_proc = value_proc
      @_reset_proc = reset
    end

    def _content        = self
    def _value          = @_value_proc.call
    def _reset          = @_reset_proc&.call
    def _set_value(val)  = (@_current_value = val)
    def _current_value   = @_current_value ||= 0
  end
end
