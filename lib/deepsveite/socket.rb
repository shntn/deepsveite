# frozen_string_literal: true

module DeepSveite
  class Socket
    attr_accessor :_parent, :_name, :_method, :_sim, :_width, :_probes

    def initialize(method: nil, width: nil)
      @_method = method  # ターゲット側のハンドラメソッド名（Symbol）
      @_width  = width   # nil / Integer / Hash{key => width}
      @_parent = nil     # EnvironmentBuilder が設定
      @_name   = nil     # EnvironmentBuilder が設定
      @_sim    = nil     # EnvironmentBuilder が設定
      @_bound  = nil     # bind 先のターゲット Socket
      @_probes = {}      # key => VCDProbe
    end

    def bind(target_socket)
      @_bound = target_socket
    end

    def method_missing(name, *args, &block)
      if @_bound&._method == name
        result = @_sim.socket_transport(@_bound, name, args, &block)
        Fiber.yield(:next_cycle)
        result
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      (@_bound&._method == name) || super
    end
  end
end
