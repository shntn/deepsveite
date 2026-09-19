# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

# examples/ex_*.rb を実際に実行し、正常終了と主要な出力を確認する
class TestExamples < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # example 名 => [期待する出力の断片, 出力される VCD ファイル]
  EXPECTATIONS = {
    "ex_wire.rb"       => [["internal : 5", "dout : 5"], []],
    "ex_reg.rb"        => [["q = 1", "q = 2", "q = 3", "q = 0"], []],
    "ex_bitselect.rb"  => [["bus = 0b10111010  upper=0xb  lower=0xa", "status = 0b00110001  ready=1  cycle_count=3"], []],
    "ex_array.rb"      => [["read  mem[0] = 0x11", "read  mem[7] = 0x88", "sel=7 Black    → R=0x00 G=0x00 B=0x00  OK"], ["ram.vcd"]],
    "ex_socket.rb"     => [["0x100=AB, 0x101=CD, 0xFFF=FF"], []],
    "ex_socket_vcd.rb" => [["0x100=AB, 0x101=CD, 0xFFF=FF"], ["socket_signals.vcd"]],
    "ex_fifo.rb"       => [["write 4", "read 0", "read 4"], []],
    "ex_event.rb"      => [["Event A triggered.", "Deferred event A triggered.", "event A or B triggered.", "event A and B triggered."], []],
    "ex_rtl_tlm.rb"    => [["Processor: added 30,  result = 60", "Monitor:   count = 5"], []],
    "ex_tlm_vcd.rb"    => [["consumed: 10", "consumed: 80"], ["tlm_signals.vcd"]],
    "ex_vcd.rb"        => [["counter.vcd"], ["counter.vcd"]],
    "ex_sap1.rb"       => [["Binary Display : 6"], ["sap1.vcd"]]
  }.freeze

  def run_example(name)
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, "examples"))
      output, status = Open3.capture2e(
        RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "examples", name),
        chdir: dir
      )
      yield output, status, File.join(dir, "examples")
    end
  end

  EXPECTATIONS.each do |name, (fragments, vcd_files)|
    define_method("test_#{name.sub('.rb', '')}") do
      run_example(name) do |output, status, vcd_dir|
        assert status.success?, "#{name} が異常終了した:\n#{output}"
        fragments.each { |fragment| assert_includes output, fragment }
        vcd_files.each do |vcd|
          path = File.join(vcd_dir, vcd)
          assert File.exist?(path), "#{vcd} が出力されていない"
          assert_includes File.read(path), "$enddefinitions $end"
        end
      end
    end
  end

  # 新しい example を追加したときにテストの追加を忘れないようにする
  def test_every_example_has_expectations
    examples = Dir[File.join(ROOT, "examples", "ex_*.rb")].map { |path| File.basename(path) }.sort
    assert_equal examples, EXPECTATIONS.keys.sort
  end
end
