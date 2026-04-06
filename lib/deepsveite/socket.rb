# frozen_string_literal: true

module DeepSveite
  class Socket
    attr_accessor :_parent, :_name, :_method, :_sim, :_payload_class, :_probes

    def initialize(method: nil, payload: nil)
      @_method        = method   # ターゲット側のハンドラメソッド名（Symbol）
      @_payload_class = payload  # DS::Payload サブクラス
      @_parent = nil             # EnvironmentBuilder が設定
      @_name   = nil             # EnvironmentBuilder が設定
      @_sim    = nil             # EnvironmentBuilder が設定
      @_bound  = nil             # bind 先のターゲット Socket
      @_probes = {}              # field_name => VCDProbe
    end

    def bind(target_socket)
      @_bound = target_socket
    end

    def method_missing(name, *args, &block)
      if @_bound&._method == name
        payload = _build_payload(args)
        result  = @_sim.socket_transport(@_bound, name, payload, &block)
        Fiber.yield(:next_cycle)
        result
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      (@_bound&._method == name) || super
    end

    private

    def _build_payload(args)
      pc = @_bound._payload_class
      if args.length == 1 && args[0].is_a?(Payload)
        args[0]
      elsif pc && args.length == 1 && args[0].is_a?(Hash)
        pc.new(**args[0])
      elsif pc
        pc.new
      else
        raise ArgumentError, "Socket has no payload class defined on the target side"
      end
    end
  end
end
