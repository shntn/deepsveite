# frozen_string_literal: true

module DeepSveite
  class Wire < DeepSveite::Signal
    attr_accessor :_width, :_value, :_pending, :_name, :_parent, :_content, :_input, :_output, :_is_port
    def initialize(init: 0, width: 1)
      @_width = width
      @_value = nil
      @_pending = _mask(init)
      @_old = nil
      @_name = nil
      @_parent = nil
      @_register_destination = []
      @_edge_destinations = []
      @_content = self
      @_input = true
      @_output = true
      @_is_port = false
      @_writers_this_step = Set.new
      super()
    end

    def _register_destination(process)
      if self == @_content
        @_register_destination << process
      else
        @_content._register_destination(process)
      end
    end

    def _check_driver(process)
      return if process.nil?
      if self == @_content
        @_writers_this_step.add(process)
        (DeepSveite._process_written_signals[process] ||= Set.new).add(self)
      else
        @_content._check_driver(process)
      end
    end

    def _clear_writer
      if self == @_content
        @_writers_this_step.clear
      else
        @_content._clear_writer
      end
    end

    def _remove_writer(process)
      if self == @_content
        @_writers_this_step.delete(process)
      else
        @_content._remove_writer(process)
      end
    end

    def _check_multiple_drivers
      if self == @_content
        return if @_writers_this_step.size < 2
        sig     = @_name || "(unnamed)"
        writers = @_writers_this_step.map { |m| _process_label(m) }.join(" and ")
        raise "Multiple drivers on wire '#{sig}': #{writers}"
      else
        @_content._check_multiple_drivers
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

    def [](selector)
      unless @_input
        raise "Reg #{@_name} is not an input"
      end
      val = @_content._value || 0
      case selector
      when Integer
        (val >> selector) & 1
      when Range
        lo, hi = selector.min, selector.max
        mask = (1 << (hi - lo + 1)) - 1
        (val >> lo) & mask
      end
    end

    def []=(selector, new_val)
      unless @_output
        raise "Wire #{@_name} is not an output"
      end
      @_content._check_driver(DeepSveite.current_process)
      current = @_content._pending || 0
      case selector
      when Integer
        bit = new_val == 0 ? 0 : 1
        @_content._pending = @_content._mask(bit == 0 ? current & ~(1 << selector) : current | (1 << selector))
      when Range
        lo, hi = selector.min, selector.max
        mask = (1 << (hi - lo + 1)) - 1
        @_content._pending = @_content._mask((current & ~(mask << lo)) | ((new_val & mask) << lo))
      end
      DeepSveite._active_updates.add(@_content)
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
      @_content._check_driver(DeepSveite.current_process)
      @_content._pending = @_content._mask(value)
      DeepSveite._active_updates.add(@_content)
    end

    def _update
      @_old = @_value
      return [] if @_value == @_pending
      @_value = @_pending
      @_register_destination + _edge_methods
    end

    private

    def _process_label(method)
      method.respond_to?(:receiver) ? "#{method.receiver.class}##{method.name}" : method.to_s
    end
  end
end
