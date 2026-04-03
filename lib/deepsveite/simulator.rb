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
      @_fifo_collections = []
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

    def socket_transport(target_socket, method_name, args, &block)
      # VCD モニタリングポイント（将来実装）
      target_socket._parent.send(method_name, *args, &block)
    end

    def register_fifo_collection(fifo)
      @_fifo_collections << fifo
    end

    def register_tlm_process(method)
      @_tlm_queue << Fiber.new { method.call }
    end

    def run(&halt_condition)
      if block_given?
        loop do
          step
          break if halt_condition.call
        end
      else
        loop do
          _tlm_cycle
          _tlm_clock_notification
          break if @_tlm_queue.empty? && @_pending_tlm_fibers.empty?
        end
      end
    end

    def step
      @_clock.w = @_clock.w == 1 ? 0 : 1
      _update_pre_active
      _rtl_cycle
      _tlm_cycle
      _clock_notification_phase
    end

    def _rtl_cycle
      _evaluate_conditions
      _flush_pending_rtl_methods
      _run_delta_cycles
    end

    private

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
        method.call
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
      when :next_cycle then @_pending_tlm_fibers << fiber
      when :fifo_wait  then # FIFO が管理。_clock_tick で起床
      # 将来: when Event など
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
      _tlm_clock_notification
    end
  end
end