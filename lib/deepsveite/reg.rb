# frozen_string_literal: true

module DeepSveite
  class Reg < DeepSveite::Signal
    attr_accessor :_width, :_value, :_pending, :_name, :_parent, :_content, :_input, :_output, :_is_port
    def initialize(width: 1)
      @_width = width
      @_value = nil
      @_pending = 0
      @_old = nil
      @_name = nil
      @_parent = nil
      @_register_destination = []
      @_content = self
      @_input = true
      @_output = true
      @_is_port = false
      super()
    end

    def _register_destination(process)
      if self == @_content
        @_register_destination << process
      else
        @_content._register_destination(process)
      end
    end

    def in
      obj = DeepSveite::Reg.new(width: @_width)
      obj._content = @_content
      obj._input = @_input
      obj._output = false
      obj._is_port = true
      obj
    end

    def out
      obj = DeepSveite::Reg.new(width: @_width)
      obj._content = @_content
      obj._input = false
      obj._output = @_output
      obj._is_port = true
      obj
    end

    def posedge
      @_value != @_old && @_value > 0
    end

    def negedge
      @_value != @_old && @_value == 0
    end

    def r
      @_content._value || 0
    end

    def r=(value)
      unless @_output
        raise "Reg #{@_name} is not an output"
      end
      @_content._pending = value
    end

    def _update
      @_old = @_value
      if @_value == @_pending
        return []
      end
      @_value = @_pending
      @_register_destination
    end
  end
end