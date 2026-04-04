# frozen_string_literal: true

module DeepSveite
  class Simulator
    def initialize(test_bench, clock = nil)
      @tb = test_bench
      @eb = DeepSveite::EnvironmentBuilder.new
      @_clock = clock || DeepSveite::Wire.new
      @_pre_active_collections = []
      @_rtl_conditions = []
      @_rtl_collections = []
      @_reg_collections = []
      @_rtl_eval_queue = []
      @_pending_rtl_methods = []
      @_tlm_queue = []
      @_pending_tlm_fibers = []
      @_all_tlm_fibers = []
      @_fifo_collections = []
      @_socket_collections = []
      @_tlm_vcd_collections = []
      @_vcd = nil
      @_step_count = 0
    end

    def build
      @eb.build(self, @tb)
      _rtl_update
      _clock_notification_phase
    end

    def register_pre_active_collections(signals)
      @_pre_active_collections |= signals
      @_rtl_collections |= signals
    end

    def register_rtl_condition(edge_trigger)
      @_rtl_conditions ||= []
      @_rtl_conditions << edge_trigger
    end

    def register_rtl_collections(signal)
      @_rtl_collections << signal
    end

    def register_reg_collections(signal)
      @_reg_collections << signal
    end

    def _attach_vcd(vcd)
      @_vcd = vcd
    end

    def socket_transport(target_socket, method_name, args, &block)
      result = target_socket._parent.send(method_name, *args, &block)
      if @_vcd
        _record_socket_result(target_socket, result)
        @_step_count += 1
        @_vcd._tick(@_step_count)
      end
      result
    end

    def register_fifo_collection(fifo)
      @_fifo_collections << fifo
    end

    def register_socket_collection(socket)
      @_socket_collections << socket
    end

    def register_tlm_vcd_probe(probe)
      @_tlm_vcd_collections << probe
    end

    def _tlm_notify_immediate(fibers)
      @_tlm_queue |= fibers
    end

    def _tlm_notify_deferred(fibers)
      @_pending_tlm_fibers |= fibers
    end

    def register_tlm_process(method)
      fiber = Fiber.new { method.call }
      @_all_tlm_fibers << fiber
      @_pending_tlm_fibers << fiber
    end

    def run(&halt_condition)
      if block_given?
        loop do
          step
          break if halt_condition.call
        end
      else
        loop do
          @_step_count += 1
          _tlm_cycle
          _tlm_clock_notification
          @_vcd&._tick(@_step_count)
          break if @_all_tlm_fibers.all? { |f| !f.alive? }
        end
      end
    end

    def step
      @_step_count += 1
      @_clock.w = @_clock.w == 1 ? 0 : 1
      _clear_all_writers
      _update_pre_active
      _rtl_cycle
      _tlm_cycle
      _clock_notification_phase
      @_vcd&._tick(@_step_count)
    end

    def _rtl_cycle
      _evaluate_conditions
      _flush_pending_rtl_methods
      _run_delta_cycles
      _check_rtl_multiple_drivers
    end

    private

    def _record_socket_result(socket, result)
      case result
      when Integer
        w = socket._width.is_a?(Integer) ? socket._width : 64
        _ensure_socket_probe(socket, nil, w)
        socket._probes[nil]._set_value(result)
      when Hash
        result.each do |key, val|
          next unless val.is_a?(Integer)
          w = socket._width.is_a?(Hash) ? (socket._width[key] || 64) : (socket._width || 64)
          _ensure_socket_probe(socket, key, w)
          socket._probes[key]._set_value(val)
        end
      end
    end

    def _ensure_socket_probe(socket, key, width)
      return if socket._probes.key?(key)
      name  = key ? "#{socket._name}_#{key}" : socket._name
      probe = VCDProbe.new(name: name, parent: socket._parent, width: width) do
        socket._probes[key]._current_value
      end
      socket._probes[key] = probe
      register_tlm_vcd_probe(probe)
      @_vcd._register_probe(probe)
    end

    def _clear_all_writers
      (@_rtl_collections + @_reg_collections).each(&:_clear_writer)
      DeepSveite._process_written_signals.clear
    end

    def _run_delta_cycles
      delta_cycles = 0
      process_counts = Hash.new(0)

      loop do
        delta_cycles += 1
        _check_delta_cycles(delta_cycles)
        _execute_eval_queue(process_counts)
        _rtl_update
        break unless @_rtl_eval_queue.any?
      end
    end

    def _check_delta_cycles(delta_cycles)
      if delta_cycles > 1000
        raise "Infinite loop detected: maximum delta cycles (1000) exceeded"
      end
    end

    def _execute_eval_queue(process_counts)
      queue = @_rtl_eval_queue.dup
      queue.each do |method|
        _check_process_execution_limit(method, process_counts)
        _clear_process_written_signals(method)
        begin
          DeepSveite.current_process = method
          method.call
        ensure
          DeepSveite.current_process = nil
        end
      end
    end

    def _clear_process_written_signals(process)
      written = DeepSveite._process_written_signals[process]
      return unless written
      written.each { |signal| signal._remove_writer(process) }
      written.clear
    end

    def _check_rtl_multiple_drivers
      seen = Set.new
      (@_rtl_collections + @_reg_collections).each do |signal|
        content = signal._content
        next if seen.include?(content)
        seen.add(content)
        content._check_multiple_drivers
      end
    end

    def _check_process_execution_limit(method, process_counts)
      process_counts[method] += 1
      if process_counts[method] > 100
        method_name = if method.respond_to?(:receiver) && method.respond_to?(:name)
                        "#{method.receiver.class}##{method.name}"
                      else
                        method.to_s
                      end
        raise "Infinite loop detected: process #{method_name} executed more than 100 times in a single step"
      end
    end

    def _evaluate_conditions
      @_rtl_conditions.each do |trigger|
        @_rtl_eval_queue << trigger.method if trigger.met?
      end
    end

    def _rtl_update
      @_rtl_eval_queue.clear
      @_rtl_collections.each do |signal|
        methods = signal._update
        @_rtl_eval_queue |= methods
      end
    end

    def _update_pre_active
      @_pre_active_collections.each do |signal|
        methods = signal._update
        @_rtl_eval_queue |= methods
      end
    end

    def _tlm_cycle
      until @_tlm_queue.empty?
        queue = @_tlm_queue.dup
        @_tlm_queue.clear
        queue.each do |fiber|
          result = fiber.resume
          _handle_tlm_fiber(fiber, result) if fiber.alive?
        end
      end
    end

    def _flush_pending_rtl_methods
      @_rtl_eval_queue |= @_pending_rtl_methods
      @_pending_rtl_methods.clear
    end

    def _handle_tlm_fiber(fiber, result)
      case result
      when :next_cycle  then @_pending_tlm_fibers << fiber
      when :fifo_wait   then # FIFO が管理。_clock_tick で起床
      when :event_wait  then # Event が管理。notify/_notify_deferred で起床
      end
    end

    def _tlm_clock_notification
      @_fifo_collections.each { |fifo| @_tlm_queue |= fifo._clock_tick }
      @_tlm_queue |= @_pending_tlm_fibers
      @_pending_tlm_fibers.clear
    end

    def _clock_notification_phase
      @_reg_collections.each do |reg|
        @_pending_rtl_methods |= reg._update
      end
      _tlm_clock_notification if @_clock.w == 1
    end
  end
end