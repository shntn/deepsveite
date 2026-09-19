# frozen_string_literal: true

SIGNAL_CLASSES = [DeepSveite::Wire, DeepSveite::Reg, DeepSveite::WireArray, DeepSveite::RegArray]

module DeepSveite
  class EnvironmentBuilder
    def initialize
      @modules = []
    end

    def build(sim, mod)
      if mod.is_a?(DeepSveite::TestBench)
        _register_testbench_signals_to_simulator(sim, mod)
        _register_fifos(sim, mod)
        _register_events(sim, mod)
      else
        _register_signals_to_simulator(sim, mod)
        _register_signal_arrays(sim, mod)
        _register_processes_to_wire(sim, mod)
        _register_processes_to_reg(sim, mod)
        _register_sockets(sim, mod)
        _register_tlm_processes(sim, mod)
        _register_fifos(sim, mod)
        _register_events(sim, mod)
        _register_vcd_signals(sim, mod)
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
        if value.is_a?(DeepSveite::Reg)
          sim.register_reg_collections(value)
        else
          sim.register_rtl_collections(value)
        end
      end
    end

    def _register_processes_to_wire(sim, mod)
      mod.class._pending_combinational.each do |setup|
        method = mod.method(setup[:method])
        sim.register_comb_process(method)
        reads = setup[:reads] || _collect_signals(mod, type: :input)

        reads.each do |s_name|
          signal = mod.instance_variable_get("@#{s_name}")
          signal._register_destination method
        end

        writes = setup[:writes] || []
        writes.each do |s_name|
          signal = mod.instance_variable_get("@#{s_name}")
          content = signal._content
          sim.register_rtl_collections(content) unless content.is_a?(DeepSveite::Reg)
        end
      end
    end

    def _collect_signals(mod, type: :input)
      mod.instance_variables.each_with_object([]) do |ivar, collection|
        next if ivar.to_s.start_with?("@_")
        value = mod.instance_variable_get(ivar)
        next unless _signal?(value)
        if type == :input
          collection << ivar.to_s[1..].to_sym if value._input
        elsif type == :output
          collection << ivar.to_s[1..].to_sym if value._output
        end
      end
    end

    def _register_sockets(sim, mod)
      mod.instance_variables.each do |ivar|
        next if ivar.to_s.start_with?("@_")
        value = mod.instance_variable_get(ivar)
        next unless value.is_a?(DeepSveite::Socket)
        _set_info_to_instance(value, mod, ivar.to_s[1..])
        value._sim = sim
        sim.register_socket_collection(value) if value._method  # ターゲット側のみ登録
      end
    end

    def _register_tlm_processes(sim, mod)
      mod.class._pending_process.each do |setup|
        method = mod.method(setup[:method])
        sim.register_tlm_process(method)
      end
    end

    def _register_events(sim, mod)
      mod.instance_variables.each do |ivar|
        next if ivar.to_s.start_with?("@_")
        value = mod.instance_variable_get(ivar)
        next unless value.is_a?(DeepSveite::Event)
        _set_info_to_instance(value, mod, ivar.to_s[1..])
        value._sim = sim
        sim.register_tlm_vcd_probe(value._vcd_probe)
      end
    end

    def _register_signal_arrays(sim, mod)
      mod.instance_variables.each do |ivar|
        next if ivar.to_s.start_with?("@_")
        value = mod.instance_variable_get(ivar)
        array_name = ivar.to_s[1..]

        case value
        when DeepSveite::RegArray
          value._parent = mod
          value._name   = array_name
          value._elements.each_with_index do |elem, i|
            elem._parent = mod
            elem._name   = "#{array_name}[#{i}]"
            sim.register_reg_collections(elem)
          end
        when DeepSveite::WireArray
          value._parent = mod
          value._name   = array_name
          value._elements.each_with_index do |elem, i|
            elem._parent = mod
            elem._name   = "#{array_name}[#{i}]"
            sim.register_rtl_collections(elem)
          end
        end
      end
    end

    def _register_fifos(sim, mod)
      mod.instance_variables.each do |ivar|
        next if ivar.to_s.start_with?("@_")
        value = mod.instance_variable_get(ivar)
        next unless value.is_a?(DeepSveite::FIFO)
        _set_info_to_instance(value, mod, ivar.to_s[1..])
        sim.register_fifo_collection(value)
        value._vcd_probes.each { |p| sim.register_tlm_vcd_probe(p) }
      end
    end

    def _register_vcd_signals(sim, mod)
      mod.class._pending_vcd_signals.each do |defn|
        name  = defn[:name]
        width = defn[:width]
        size  = defn[:size]

        if size
          # 配列: build 時に size 本のプローブを静的登録
          size.times do |i|
            probe = VCDProbe.new(name: "#{name}[#{i}]", parent: mod, width: width) do
              arr = mod.instance_variable_get(:"@#{name}")
              arr.is_a?(Array) && arr[i].is_a?(Integer) ? arr[i] : 0
            end
            sim.register_tlm_vcd_probe(probe)
          end
        else
          # スカラー / ハッシュ: 動的モニタとして登録（型は実行時に判定）
          sim.register_vcd_signal_monitor(mod, name, width)
        end
      end
    end

    def _register_processes_to_reg(sim, mod)
      mod.class._pending_sequential.each do |setup|
        method = mod.method(setup[:method])

        setup[:cond].each do |cond|
          signal = mod.instance_variable_get("@#{cond.name}")
          signal._register_edge_destination(cond.edge, method)
        end
      end
    end
  end
end
