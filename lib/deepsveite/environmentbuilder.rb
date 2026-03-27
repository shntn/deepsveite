# frozen_string_literal: true

module DeepSveite
  class EnvironmentBuilder
    def initialize
      @modules = []
    end

    def build(sim, mod)
      _register_signals_to_simulator(sim, mod)
      _register_processes_to_signal(mod)
      _recursive_module(sim, mod)
    end

    private

    def _recursive_module(sim, mod)
      mod.instance_variables.each do |ivar|
        instance = mod.instance_variable_get(ivar)
        next if !(instance.class < DeepSveite::Module) || instance.class <= DeepSveite::TestBench

        _set_info_to_instance(instance, mod, ivar.to_s[1..])
        build(sim, instance)
      end
    end

    def _set_info_to_instance(instance, parent, name)
      instance._parent = parent
      instance._name = name
    end

    def _register_signals_to_simulator(sim, mod)
      mod.instance_variables.each do |ivar|
        value = mod.instance_variable_get(ivar)
        next unless value.class <= DeepSveite::Wire

        _set_info_to_instance(value, mod, ivar.to_s[1..])
        sim.register_wire value if value == value._content
      end
    end

    def _register_processes_to_signal(mod)
      mod.class._pending_combinational.each do |setup|
        method = mod.method(setup[:method])
        setup[:reads].each do |s_name|
          signal = mod.instance_variable_get("@#{s_name}")
          signal._register_destination method
        end
      end
    end
  end
end
