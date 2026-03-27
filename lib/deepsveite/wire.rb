# frozen_string_literal: true

module DeepSveite
  class Wire < DeepSveite::Signal
    attr_accessor :_width, :_value, :_pending, :_name, :_parent, :_content, :_input, :_output
    def initialize(width: 1)
      @_width = width
      @_value = nil
      @_pending = 0
      @_name = nil
      @_parent = nil
      @_register_source = []
      @_register_destination = []
      @_content = self
      @_input = true
      @_output = true
      super()
    end

    def _regist_source(method)
      @_register_source << method
    end

    def _register_destination(process)
      if self == @_content
        @_register_destination << process
      else
        @_content._register_destination(process)
      end
    end

    def in
      obj = DeepSveite::Wire.new(width: @_width)
      obj._content = @_content
      obj._input = @_input
      obj._output = false
      obj
    end

    def out
      obj = DeepSveite::Wire.new(width: @_width)
      obj._content = @_content
      obj._input = false
      obj._output = @_output
      obj
    end

    def w
      unless @_input
        raise "Wire #{@_name} is not an input"
      end
      @_content._value || 0
    end

    def w=(value)
      unless @_output
        raise "Wire #{@_name} is not an output"
      end
      @_content._pending = value
    end

    def _update
      if @_value != @_pending
        @_value = @_pending
        @_register_destination
      else
        []
      end
    end
  end
end