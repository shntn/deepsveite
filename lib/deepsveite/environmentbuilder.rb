# frozen_string_literal: true

SIGNAL_CLASSES = [DeepSveite::Wire, DeepSveite::Reg]

module DeepSveite
  class EnvironmentBuilder
    def initialize
      @modules = []
    end

    def build(sim, mod)
      _register_signals_to_simulator(sim, mod)
      unless mod.is_a?(DeepSveite::TestBench)
        _register_processes_to_wire(mod)
        _register_processes_to_reg(sim, mod)
      end
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

    def _signal?(instance)
      SIGNAL_CLASSES.any? { |klass| instance.is_a?(klass) }
    end

    def _set_info_to_instance(instance, parent, name)
      instance._parent = parent
      instance._name = name
    end

    def _register_signals_to_simulator(sim, mod)
      mod.instance_variables.each do |ivar|
        value = mod.instance_variable_get(ivar)
        next unless _signal?(value)
        _set_info_to_instance(value, mod, ivar.to_s[1..])
        next unless value == value._content
        value.is_a?(DeepSveite::Reg) ? sim.register_reg(value) : sim.register_wire(value)
      end
    end

    def _register_processes_to_wire(mod)
      mod.class._pending_combinational.each do |setup|
        method = mod.method(setup[:method])
        setup[:reads].each do |s_name|
          signal = mod.instance_variable_get("@#{s_name}")
          signal._register_destination method
        end
      end
    end

    def _register_processes_to_reg(sim, mod)
      mod.class._pending_sequential.each do |setup|
        method = mod.method(setup[:method])
        setup[:cond].each do |cond|
          case cond
          when false, nil
            next
          when true
            sim.register_reg_condition(nil, edge: nil, method: method)
          when String
            signal_name, edge = cond.split(".")
            reg = mod.instance_variable_get("@#{signal_name}")._content
            sim.register_reg_condition(reg, edge: edge.to_sym, method: method)
          else
            raise ArgumentError, "invalid cond value: #{cond.inspect}"
          end
        end
      end
    end
  end
end
