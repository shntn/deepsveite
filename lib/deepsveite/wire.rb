# frozen_string_literal: true

module DeepSveite
  class Wire < DeepSveite::Signal
    attr_accessor :_width, :_value, :_pending, :_name, :_parent, :_content, :_input, :_output, :_is_port
    def initialize(init: 0, width: 1)
      @_width = width
      @_value = nil
      @_pending = init
      @_old = nil
      @_name = nil
      @_parent = nil
      @_register_source = []
      @_register_destination = []
      @_content = self
      @_input = true
      @_output = true
      @_is_port = false
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
      obj._is_port = true
      obj
    end

    def out
      obj = DeepSveite::Wire.new(width: @_width)
      obj._content = @_content
      # TODO :
      # ビットセレクト、パートセレクトによる更新ができないため、
      # 暫定処置として読み出しを許可
      obj._input = @_input
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

    def w
      @_content._value || 0
    end

    def w=(value)
      unless @_output
        raise "Wire #{@_name} is not an output"
      end
      @_content._pending = value
    end

    def _update
      @_old = @_value
      if @_value != @_pending
        @_value = @_pending
        @_register_destination
      else
        []
      end
    end
  end
end