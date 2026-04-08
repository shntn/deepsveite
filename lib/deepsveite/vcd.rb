# frozen_string_literal: true

module DeepSveite
  class VCD
    # sim.build の後に生成する。build 時点の初期値を time=0 として記録し、
    # 以降は sim.step ごとに変化した信号を追記する。
    #
    # 使用例:
    #   sim.build
    #   vcd = DeepSveite::VCD.new(sim, filename: "dump.vcd")
    #   sim.run { n >= 10 }
    #   vcd.write

    def initialize(sim, filename: "dump.vcd", timescale: "1 ns", time_step: 10)
      @sim       = sim
      @filename  = filename
      @timescale = timescale
      @time_step = time_step

      @signals        = _collect_signals
      @id_map         = _assign_ids
      @initial_values = {}  # time=0 のダンプ用（変化しない）
      @last_values    = {}  # 変化検出用（tick ごとに更新）
      @changes        = []  # [[time, id, value, width], ...]

      _record_initial_values

      sim._attach_vcd(self)
    end

    # sim.step の末尾から呼ばれる。変化した信号を記録する。
    def _tick(step_count)
      time = step_count * @time_step
      @signals.each do |sig|
        val = _to_int(sig._value)
        next if @last_values[sig] == val
        @changes << [time, @id_map[sig], val, sig._width]
        @last_values[sig] = val
      end
      @sim.instance_variable_get(:@_tlm_vcd_collections).each(&:_reset)
    end

    # VCD ファイルを書き出す
    def write(filename = @filename)
      File.open(filename, "w") { |f| _write(f) }
    end

    # シミュレーション中に動的に追加されるプローブを登録する
    def _register_probe(probe)
      return if @signals.include?(probe)
      @signals << probe
      @id_map[probe]         = (33 + @id_map.size).chr
      @initial_values[probe] = 0
      @last_values[probe]    = 0
    end

    private

    # canonical な信号（ポートビューを除く）と TLM プローブを収集
    def _collect_signals
      rtl    = @sim.instance_variable_get(:@_rtl_collections)
      reg    = @sim.instance_variable_get(:@_reg_collections)
      probes = @sim.instance_variable_get(:@_tlm_vcd_collections)
      (rtl + reg).uniq.select { |sig| sig == sig._content } + probes
    end

    # 各信号に VCD 識別子（'!' 〜）を割り当てる
    def _assign_ids
      @signals.each_with_index.to_h { |sig, i| [sig, (33 + i).chr] }
    end

    # build 後の初期値を time=0 として記録
    def _record_initial_values
      @signals.each do |sig|
        val = _to_int(sig._value)
        @initial_values[sig] = val
        @last_values[sig]    = val
      end
    end

    # _parent チェーンを辿って階層ツリーを構築する
    # ツリーノード: { name: String, children: { name => node }, signals: [Signal] }
    def _build_scope_tree
      tb   = @sim.instance_variable_get(:@tb)
      root = { name: tb.class.name.split("::").last, children: {}, signals: [] }

      @signals.each do |sig|
        # ルート (TestBench) の直下まで親チェーンを収集
        chain = []
        node  = sig._parent
        while node && node._parent
          chain.unshift(node._name)
          node = node._parent
        end

        # ツリーを掘り進んでノードを作成
        current = root
        chain.each do |name|
          current[:children][name] ||= { name: name, children: {}, signals: [] }
          current = current[:children][name]
        end
        current[:signals] << sig
      end

      root
    end

    def _write(f)
      f.puts "$timescale #{@timescale} $end"
      f.puts "$date #{Time.now.strftime('%Y/%m/%d %H:%M:%S')} $end"
      f.puts "$version DeepSveite VCD $end"
      f.puts ""

      _write_scope(f, _build_scope_tree)
      f.puts ""
      f.puts "$enddefinitions $end"
      f.puts ""

      # 初期値ダンプ（VCD 生成時点の値）
      f.puts "$dumpvars"
      @signals.each { |sig| _write_value(f, @id_map[sig], @initial_values[sig], sig._width) }
      f.puts "$end"
      f.puts ""

      # 変化ログ
      @changes.group_by { |c| c[0] }.sort.each do |time, entries|
        f.puts "##{time}"
        entries.each { |_, id, val, width| _write_value(f, id, val, width) }
      end
    end

    def _write_scope(f, node, indent = "")
      f.puts "#{indent}$scope module #{node[:name]} $end"
      inner = indent + "  "

      node[:signals].each do |sig|
        type = sig.is_a?(Reg) ? "reg" : "wire"
        f.puts "#{inner}$var #{type} #{sig._width} #{@id_map[sig]} #{sig._name} $end"
      end

      node[:children].each_value do |child|
        _write_scope(f, child, inner)
      end

      f.puts "#{indent}$upscope $end"
    end

    def _write_value(f, id, val, width)
      # 負数・オーバーフローを幅でマスクして 2 の補数表現に正規化
      mask    = (1 << width) - 1
      int_val = _to_int(val) & mask
      if width == 1
        f.puts "#{int_val}#{id}"
      else
        f.puts "b#{int_val.to_s(2).rjust(width, '0')} #{id}"
      end
    end

    # Wire / Reg には true/false が入ることがある（Ruby 比較式の結果）
    # Payload など整数変換できないオブジェクトは 0 として扱う
    def _to_int(val)
      case val
      when true    then 1
      when false   then 0
      when nil     then 0
      when Integer then val
      else val.respond_to?(:to_i) ? val.to_i : 0
      end
    end
  end
end
