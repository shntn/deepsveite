# frozen_string_literal: true

module DeepSveite
  class RegArray
    attr_accessor :_name, :_parent

    def initialize(width: 1, size: 1)
      @_width    = width
      @_size     = size
      @_elements = Array.new(size) { Reg.new(width: width) }
      @_name     = nil
      @_parent   = nil
    end

    # selector に Integer（ビット）か Range（ビット範囲）を渡すと、そのビットだけを読む
    def [](index, selector = nil)
      elem = _element(index)
      selector.nil? ? elem.r : elem[_check_selector(selector)]
    end

    # RTL プロセス内は NBA、プロセス外（TLM / TestBench）は即時反映
    def []=(index, *args)
      raise ArgumentError, "wrong number of arguments (given #{args.size + 1}, expected 2..3)" unless args.size.between?(1, 2)
      selector, value = args.size == 2 ? args : [nil, args.first]
      elem = _element(index)
      if selector.nil?
        elem.r = value
      else
        elem[_check_selector(selector)] = value
      end
      return if DeepSveite.current_process
      DeepSveite._nba_updates.delete(elem)
      DeepSveite._pending_evals.merge(elem._update)
    end

    def _input  = true
    def _output = true

    def _register_destination(process)
      @_elements.each { |elem| elem._register_destination(process) }
    end

    def _elements = @_elements

    private

    def _check_selector(selector)
      return selector if selector.is_a?(Integer) || selector.is_a?(Range)
      raise ArgumentError, "bit selector must be an Integer or a Range (given #{selector.inspect})"
    end

    def _element(index)
      unless index.is_a?(Integer) && index.between?(0, @_size - 1)
        raise IndexError, "index #{index} out of range (size #{@_size}) in #{@_name || self.class}"
      end
      @_elements[index]
    end
  end
end
