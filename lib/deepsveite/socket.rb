# frozen_string_literal: true

module DeepSveite
  class Socket
    attr_accessor :_parent, :_name, :_method, :_sim

    def initialize(method: nil)
      @_method = method  # ターゲット側のハンドラメソッド名（Symbol）
      @_parent = nil     # EnvironmentBuilder が設定
      @_name   = nil     # EnvironmentBuilder が設定
      @_sim    = nil     # EnvironmentBuilder が設定
      @_bound  = nil     # bind 先のターゲット Socket
    end

    def bind(target_socket)
      @_bound = target_socket
    end

    def method_missing(name, *args, &block)
      if @_bound&._method == name
        @_sim.socket_transport(@_bound, name, args, &block)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      (@_bound&._method == name) || super
    end
  end
end
