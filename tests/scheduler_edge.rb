# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

# -----------------------------------------------------------------------
# テスト用モジュール
# -----------------------------------------------------------------------

# ld=1 で a, b をロードし、ld=0 では a と b を入れ替える
class EdgeSwap < DeepSveite::Module
  attr_accessor :clk, :ld, :x, :y
  attr_reader :a, :b
  always_ff :on_clk, cond: [:clk.posedge]

  def initialize
    @a = DeepSveite::Reg.new(width: 8)
    @b = DeepSveite::Reg.new(width: 8)
    super()
  end

  def on_clk
    if @ld.w == 1
      @a.r = @x.w
      @b.r = @y.w
    else
      @a.r = @b.r
      @b.r = @a.r
    end
  end
end

# 自分自身を読んで書き続ける（収束しない）組み合わせ回路
class EdgeLoop < DeepSveite::Module
  attr_reader :x
  always_comb :spin

  def initialize
    @x = DeepSveite::Wire.new(width: 8)
    super()
  end

  def spin = @x.w = @x.w + 1
end

# rst の negedge だけで動く always_ff
class EdgeResetCounter < DeepSveite::Module
  attr_accessor :rst
  attr_reader :count
  always_ff :bump, cond: [:rst.negedge]

  def initialize
    @count = DeepSveite::Reg.new(width: 8)
    super()
  end

  def bump = @count.r = @count.r + 1
end

# 入力を読まない（定数を出力する）always_comb
class EdgeConst < DeepSveite::Module
  attr_reader :out
  always_comb :drive

  def initialize
    @out = DeepSveite::Wire.new(width: 8)
    super()
  end

  def drive = @out.w = 5
end

# always_comb で作ったクロックで always_ff を動かす（ゲーテッドクロック）
class EdgeGated < DeepSveite::Module
  attr_accessor :clk, :en
  attr_reader :count
  always_comb :gate
  always_ff   :bump, cond: [:gclk.posedge]

  def initialize
    @gclk  = DeepSveite::Wire.new
    @count = DeepSveite::Reg.new(width: 8)
    super()
  end

  def gate = @gclk.w = @clk.w & @en.w
  def bump = @count.r = @count.r + 1
end

# 定数を出力する always_comb と、それを posedge で取り込む always_ff
class EdgeConstLatch < DeepSveite::Module
  attr_accessor :clk
  attr_reader :k, :q
  always_comb :drive
  always_ff   :latch, cond: [:clk.posedge]

  def initialize
    @k = DeepSveite::Wire.new(width: 8)
    @q = DeepSveite::Reg.new(width: 8)
    super()
  end

  def drive = @k.w = 5
  def latch = @q.r = @k.w
end

# 初期値を持つ入力から計算する always_comb
class EdgeInitInput < DeepSveite::Module
  attr_accessor :a
  attr_reader :y
  always_comb :calc

  def initialize
    @y = DeepSveite::Wire.new(width: 8)
    super()
  end

  def calc = @y.w = @a.w + 1
end

# 何も読まず、.out ポートにだけ書く always_comb
class EdgeOutOnly < DeepSveite::Module
  attr_accessor :y

  always_comb :drive

  def drive = @y.w = 7
end

# reads: 省略時に、Module 内の Wire を経由した多段の伝播が収束する
class EdgeAutoChain < DeepSveite::Module
  attr_accessor :a
  attr_reader :mid, :out, :self_rw
  always_comb :stage1
  always_comb :stage2
  always_comb :selfrw

  def initialize
    @mid     = DeepSveite::Wire.new(width: 8)
    @out     = DeepSveite::Wire.new(width: 8)
    @self_rw = DeepSveite::Wire.new(width: 8)
    super()
  end

  def stage1 = @mid.w = @a.w + 1
  def stage2 = @out.w = @mid.w * 2
  def selfrw = @self_rw.w = @self_rw.w | 1
end

# 評価回数を数える。出力は .out ポート（自動収集の対象外）
class EdgeCounting < DeepSveite::Module
  attr_accessor :a, :y
  attr_reader :evals
  always_comb :calc

  def initialize
    @evals = 0
    super()
  end

  def calc
    @evals += 1
    @y.w = @a.w + 1
  end
end

# 内部クロックで process を進める
class EdgeTicker < DeepSveite::Module
  attr_reader :log
  process :run

  def initialize
    @log = []
    super()
  end

  def run
    3.times do
      @log << :tick
      wait
    end
  end
end

class EdgeSwapBench < DeepSveite::TestBench
  attr_reader :clk, :ld, :x, :y, :dut

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @ld  = DeepSveite::Wire.new
    @x   = DeepSveite::Wire.new(width: 8)
    @y   = DeepSveite::Wire.new(width: 8)
    @dut = EdgeSwap.new
    @dut.clk = @clk.in
    @dut.ld  = @ld.in
    @dut.x   = @x.in
    @dut.y   = @y.in
  end
end

class EdgeSingleBench < DeepSveite::TestBench
  attr_reader :clk, :dut

  def initialize(dut)
    super()
    @clk = DeepSveite::Wire.new
    @dut = dut
  end
end

class EdgeResetBench < DeepSveite::TestBench
  attr_reader :clk, :rst, :dut

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @rst = DeepSveite::Wire.new
    @dut = EdgeResetCounter.new
    @dut.rst = @rst.in
  end
end

class EdgeGatedBench < DeepSveite::TestBench
  attr_reader :clk, :en, :dut

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @en  = DeepSveite::Wire.new
    @dut = EdgeGated.new
    @dut.clk = @clk.in
    @dut.en  = @en.in
  end
end

class EdgeAutoChainBench < DeepSveite::TestBench
  attr_reader :clk, :a, :dut

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @a   = DeepSveite::Wire.new(width: 8)
    @dut = EdgeAutoChain.new
    @dut.a = @a.in
  end
end

class EdgeCountingBench < DeepSveite::TestBench
  attr_reader :clk, :a, :y, :dut

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @a   = DeepSveite::Wire.new(width: 8)
    @y   = DeepSveite::Wire.new(width: 8)
    @dut = EdgeCounting.new
    @dut.a = @a.in
    @dut.y = @y.out
  end
end

class EdgeConstLatchBench < DeepSveite::TestBench
  attr_reader :clk, :dut

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @dut = EdgeConstLatch.new
    @dut.clk = @clk.in
  end
end

class EdgeInitInputBench < DeepSveite::TestBench
  attr_reader :clk, :dut

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @a   = DeepSveite::Wire.new(init: 3, width: 8)
    @dut = EdgeInitInput.new
    @dut.a = @a.in
  end
end

class EdgeOutOnlyBench < DeepSveite::TestBench
  attr_reader :clk, :y, :dut

  def initialize
    super()
    @clk = DeepSveite::Wire.new
    @y   = DeepSveite::Wire.new(width: 8)
    @dut = EdgeOutOnly.new
    @dut.y = @y.out
  end
end

class TestSchedulerEdge < Minitest::Test

  def build(tb, clock = tb.clk)
    sim = DeepSveite::Simulator.new(tb, clock)
    sim.build
    sim
  end

  # ---- 3. スケジューラの境界条件 ----

  # Reg 同士の入れ替えは、両方が更新前の値を読む
  def test_reg_swap_uses_old_values
    tb  = EdgeSwapBench.new
    sim = build(tb)

    tb.ld.w = 1; tb.x.w = 1; tb.y.w = 2
    sim.step  # posedge: a=1, b=2 をロード
    assert_equal [1, 2], [tb.dut.a.r, tb.dut.b.r]

    sim.step  # negedge
    tb.ld.w = 0
    sim.step  # posedge: 入れ替え
    assert_equal [2, 1], [tb.dut.a.r, tb.dut.b.r]

    sim.step  # negedge
    sim.step  # posedge: 元に戻る
    assert_equal [1, 2], [tb.dut.a.r, tb.dut.b.r]
  end

  # 収束しない組み合わせループは無限ループとして検出される
  def test_combinational_loop_is_detected
    tb = EdgeSingleBench.new(EdgeLoop.new)

    # 時刻 0 の always_comb 評価で、build 時に検出される
    err = assert_raises(RuntimeError) { build(tb) }
    assert_match(/Infinite loop detected/, err.message)
  end

  # 時刻 0 の初期化では negedge を発生させない
  def test_no_edge_event_at_time_zero
    tb  = EdgeResetBench.new
    sim = build(tb)

    2.times { sim.step }
    assert_equal 0, tb.dut.count.r
  end

  # rst が 1 → 0 に変化したときだけ negedge で起動する
  def test_negedge_fires_only_on_falling_edge
    tb  = EdgeResetBench.new
    sim = build(tb)

    tb.rst.w = 1
    sim.step  # 0 → 1: posedge なので起動しない
    assert_equal 0, tb.dut.count.r

    tb.rst.w = 0
    sim.step  # 1 → 0: negedge
    assert_equal 1, tb.dut.count.r

    sim.step  # 変化なし
    assert_equal 1, tb.dut.count.r
  end

  # 入力を読まない always_comb の出力は、step しても保たれる
  def test_constant_comb_output_is_kept_after_step
    tb  = EdgeSingleBench.new(EdgeConst.new)
    sim = build(tb)

    assert_equal 5, tb.dut.out.w
    sim.step
    assert_equal 5, tb.dut.out.w
  end

  # always_comb が作ったクロックで always_ff が同じ step 内で起動する
  def test_gated_clock_triggers_ff_in_same_step
    tb  = EdgeGatedBench.new
    sim = build(tb)

    tb.en.w = 1
    sim.step  # clk posedge → gclk posedge → bump
    assert_equal 1, tb.dut.count.r

    sim.step  # negedge
    assert_equal 1, tb.dut.count.r

    sim.step  # posedge
    assert_equal 2, tb.dut.count.r

    tb.en.w = 0
    sim.step  # negedge
    sim.step  # posedge だが gclk は上がらない
    assert_equal 2, tb.dut.count.r
  end

  # ---- 時刻 0 の always_comb ----

  # always_comb は build の時点（時刻 0）で評価され、出力が入力と整合している
  def test_comb_is_evaluated_at_time_zero
    tb  = EdgeSingleBench.new(EdgeConst.new)
    build(tb)

    assert_equal 5, tb.dut.out.w
  end

  # 初期値を持つ入力から計算する always_comb も、build の時点で評価される
  def test_comb_uses_initial_input_at_time_zero
    tb = EdgeInitInputBench.new
    build(tb)

    assert_equal 4, tb.dut.y.w
  end

  # 何も読まず .out ポートにだけ書く always_comb も、build の時点で評価される
  def test_output_only_comb_is_evaluated_at_time_zero
    tb = EdgeOutOnlyBench.new
    build(tb)

    assert_equal 7, tb.y.w
  end

  # 最初の posedge で、always_ff は always_comb の初期評価済みの出力を取り込む
  def test_ff_at_first_posedge_sees_settled_comb_output
    tb  = EdgeConstLatchBench.new
    sim = build(tb)

    sim.step  # 最初の posedge
    assert_equal 5, tb.dut.q.r
  end

  # ---- 4. reads: 省略時の自動収集 ----

  # Module 内で定義した Wire も自動収集され、多段の伝播が収束する
  def test_internal_wires_are_collected_without_reads
    tb  = EdgeAutoChainBench.new
    sim = build(tb)

    tb.a.w = 3
    sim.step
    assert_equal [4, 8, 1], [tb.dut.mid.w, tb.dut.out.w, tb.dut.self_rw.w]

    tb.a.w = 10
    sim.step
    assert_equal [11, 22], [tb.dut.mid.w, tb.dut.out.w]
  end

  # .out ポートは自動収集されないので、自分の出力の変化で再評価されない
  def test_out_port_is_not_collected
    tb  = EdgeCountingBench.new
    sim = build(tb)
    assert_equal 1, tb.dut.evals   # 時刻 0 の評価

    tb.a.w = 3
    sim.step
    assert_equal 4, tb.y.w
    assert_equal 2, tb.dut.evals   # 入力の変化による 1 回だけ（自分の出力では再評価されない）
  end

  # .out ポートは読み出せない
  def test_out_port_cannot_be_read
    tb  = EdgeCountingBench.new
    build(tb)
    assert_raises(RuntimeError) { tb.dut.y.w }
  end

  # ---- 5. シミュレータ間の状態分離 ----

  # build 前に書き込まれた更新イベントは、別のシミュレータに持ち越されない
  def test_stale_update_before_build_does_not_leak
    tb1 = EdgeCountingBench.new
    build(tb1)
    evals_after_build = tb1.dut.evals
    tb1.a.w = 3   # 更新イベントが登録されるが、tb1 は step しない

    tb2  = EdgeCountingBench.new
    sim2 = build(tb2)
    tb2.a.w = 1
    sim2.step

    assert_equal evals_after_build, tb1.dut.evals
    assert_equal 2, tb2.y.w
  end

  # 続けて作った 2 つのシミュレータが、互いに影響しない
  def test_sequential_simulators_are_independent
    tb1  = EdgeSwapBench.new
    sim1 = build(tb1)
    tb1.ld.w = 1; tb1.x.w = 7; tb1.y.w = 8
    sim1.step
    assert_equal [7, 8], [tb1.dut.a.r, tb1.dut.b.r]

    tb2  = EdgeSwapBench.new
    sim2 = build(tb2)
    tb2.ld.w = 1; tb2.x.w = 1; tb2.y.w = 2
    sim2.step
    assert_equal [1, 2], [tb2.dut.a.r, tb2.dut.b.r]
    assert_equal [7, 8], [tb1.dut.a.r, tb1.dut.b.r]
  end

  # 例外で途中終了した後でも、新しいシミュレータは正常に動く
  def test_new_simulator_works_after_an_error
    tb1 = EdgeSingleBench.new(EdgeLoop.new)
    assert_raises(RuntimeError) { build(tb1) }
    assert_nil DeepSveite.current_process

    tb2  = EdgeAutoChainBench.new
    sim2 = build(tb2)
    tb2.a.w = 3
    sim2.step
    assert_equal 8, tb2.dut.out.w
  end

  # ---- 9. 内部クロック ----

  # clock を省略した Simulator でも、step ごとに内部クロックが toggle する
  def test_internal_clock_toggles_and_wakes_tlm_processes
    tb  = DeepSveite::TestBench.new
    dut = EdgeTicker.new
    tb.instance_variable_set(:@dut, dut)
    sim = DeepSveite::Simulator.new(tb)
    sim.build

    sim.step  # posedge: process が起床キューに入る
    assert_equal 0, dut.log.size
    sim.step  # negedge: process が 1 回目の周期を実行
    assert_equal 1, dut.log.size
    sim.step
    assert_equal 1, dut.log.size
    sim.step
    assert_equal 2, dut.log.size
    2.times { sim.step }
    assert_equal 3, dut.log.size
  end
end
