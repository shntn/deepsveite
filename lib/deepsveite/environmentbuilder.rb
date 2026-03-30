# frozen_string_literal: true

SIGNAL_CLASSES = [DeepSveite::Wire, DeepSveite::Reg]

module DeepSveite
  class EnvironmentBuilder
    def initialize
      @modules = []
    end

    def build(sim, mod)
      if mod.is_a?(DeepSveite::TestBench)
        _register_testbench_signals_to_simulator(sim, mod)
      else
        _register_signals_to_simulator(sim, mod)
        _register_processes_to_wire(mod)
        _register_processes_to_reg(sim, mod)
      end
      _recursive_module(sim, mod)
    end

    private

    def _collect_instance_variable(mod, kinds)
      collection = []
      mod.instance_variables.each do |ivar|
        value = mod.instance_variable_get(ivar)
        next unless kinds.any? { |klass| value.is_a?(klass) }
        _set_info_to_instance(value, mod, ivar.to_s[1..])
        collection << value
      end
      collection
    end

    def _recursive_module(sim, mod)
      mod.instance_variables.each do |ivar|
        next if ivar.to_s.start_with?("@_")
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

    def _register_testbench_signals_to_simulator(sim, mod)
      collection = _collect_instance_variable(mod, [DeepSveite::Wire, DeepSveite::Reg])
      sim.register_pre_active_collections(collection)
    end

    def _register_signals_to_simulator(sim, mod)
      collection = _collect_instance_variable(mod, [DeepSveite::Wire, DeepSveite::Reg])
      collection.each do |value|
        next unless value == value._content
        sim.register_rtl_collections(value)
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
          signal = mod.instance_variable_get("@#{cond.name}")
          edge_trigger = EdgeTrigger.new(signal._content, cond.edge, method)
          sim.register_rtl_condition(edge_trigger)
        end
      end
    end
  end
end
