# frozen_string_literal: true

module DeepSveite
  class Simulator
    def initialize(test_bench, clock = nil)
      @tb = test_bench
      @eb = DeepSveite::EnvironmentBuilder.new
      @_clock = clock || DeepSveite::Wire.new
      @_rtl_collections = []
      @_reg_collections = []
      @_rtl_eval_queue = []
      @_tlm_queue = []
      @_pending_tlm_fibers = []
      @_all_tlm_fibers = []
      @_fifo_collections = []
      @_socket_collections = []
      @_tlm_vcd_collections = []
      @_vcd_signal_monitors = []
      @_vcd = nil
      @_step_count = 0
    end

    def build
      @eb.build(self, @tb)
      _settle_initial_values
    end

    def register_pre_active_collections(signals)
      @_rtl_collections |= signals
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

    def socket_transport(target_socket, method_name, payload, &block)
      target_socket._parent.send(method_name, payload, &block)
      if @_vcd
        _record_socket_payload(target_socket, payload)
        @_step_count += 1
        _vcd_tick
      end
      payload
    end

    def register_fifo_collection(fifo)
      @_fifo_collections << fifo
    end

    def register_socket_collection(socket)
      @_socket_collections << socket
    end

    def register_vcd_signal_monitor(mod, name, width)
      @_vcd_signal_monitors << { mod: mod, name: name, width: width, probes: {} }
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
          _vcd_tick
          break if @_tlm_queue.empty?
        end
      end
    end

    def step
      @_step_count += 1
      @_clock.w = @_clock.w == 1 ? 0 : 1
      _clear_all_writers
      _rtl_cycle
      _tlm_cycle
      _clock_notification_phase
      _vcd_tick
    end

    def _rtl_cycle
      counts = { delta: 0, process: Hash.new(0) }
      loop do
        _run_active_region(counts)
        break if DeepSveite._nba_updates.empty?
        _run_nba_region
      end
      _check_rtl_multiple_drivers
    end

    private

    def _vcd_tick
      return unless @_vcd
      _update_vcd_signal_monitors
      @_vcd._tick(@_step_count)
    end

    def _update_vcd_signal_monitors
      @_vcd_signal_monitors.each do |monitor|
        val = monitor[:mod].instance_variable_get(:"@#{monitor[:name]}")
        case val
        when Integer
          _ensure_vcd_monitor_probe(monitor, nil)
          monitor[:probes][nil]._set_value(val)
        when Hash
          val.each do |key, v|
            next unless v.is_a?(Integer)
            _ensure_vcd_monitor_probe(monitor, key)
            monitor[:probes][key]._set_value(v)
          end
        end
      end
    end

    def _ensure_vcd_monitor_probe(monitor, key)
      return if monitor[:probes].key?(key)
      probe_name = key ? "#{monitor[:name]}_#{key}" : monitor[:name].to_s
      probe = VCDProbe.new(name: probe_name, parent: monitor[:mod], width: monitor[:width]) do
        monitor[:probes][key]._current_value
      end
      monitor[:probes][key] = probe
      register_tlm_vcd_probe(probe)
      @_vcd._register_probe(probe)
    end

    def _record_socket_payload(socket, payload)
      return unless payload.is_a?(DeepSveite::Payload)
      payload.class._fields.each do |field_def|
        key = field_def[:name]
        _ensure_socket_probe(socket, key, field_def[:width])
        socket._probes[key]._set_value(payload._field_int_value(key))
      end
    end

    def _ensure_socket_probe(socket, key, width)
      return if socket._probes.key?(key)
      name  = "#{socket._name}_#{key}"
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

    def _settle_initial_values
      (@_rtl_collections + @_reg_collections).each do |signal|
        @_rtl_eval_queue |= signal._update
      end
      DeepSveite._active_updates.clear
      DeepSveite._nba_updates.clear
    end

    # Active 領域: 更新イベントを反映して評価イベントを実行し、両方が空になるまで繰り返す
    def _run_active_region(counts)
      loop do
        _apply_updates(DeepSveite._active_updates)
        break if @_rtl_eval_queue.empty?
        counts[:delta] += 1
        _check_delta_cycles(counts[:delta])
        _execute_eval_queue(counts[:process])
      end
    end

    # NBA 領域: Reg の更新イベントを反映し、感度のある評価イベントを Active に積む
    def _run_nba_region
      _apply_updates(DeepSveite._nba_updates)
    end

    def _apply_updates(updates)
      signals = updates.to_a
      updates.clear
      signals.each { |signal| @_rtl_eval_queue |= signal._update }
    end

    def _check_delta_cycles(delta_cycles)
      if delta_cycles > 1000
        raise "Infinite loop detected: maximum delta cycles (1000) exceeded"
      end
    end

    def _execute_eval_queue(process_counts)
      queue = @_rtl_eval_queue.dup
      @_rtl_eval_queue.clear
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
      _tlm_clock_notification if @_clock.w == 1
    end
  end
end