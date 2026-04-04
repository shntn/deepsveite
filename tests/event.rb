# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

# -----------------------------------------------------------------------
# 共通モジュール
#
# Bench でのモジュール登録順（instance_variable の定義順）によって
# TLM プロセスの起動順が決まる。
# Reader を Writer より先に定義することで、Reader が先に wait を呼び、
# 確実に待機状態になってから Writer が notify する。
# -----------------------------------------------------------------------

class EventWaiter < DeepSveite::Module
  attr_accessor :reader
  attr_reader   :log

  def initialize
    @log = []
    super()
  end

  process :run
  def run
    @reader.wait
    @log << :woken
  end
end

class EventNotifier < DeepSveite::Module
  attr_accessor :writer
  attr_reader   :log

  def initialize
    @log = []
    super()
  end

  process :run
  def run
    @writer.notify
    @log << :notified
  end
end

class EventNotifierDeferred < DeepSveite::Module
  attr_accessor :writer
  attr_reader   :log

  def initialize
    @log = []
    super()
  end

  process :run
  def run
    @writer.notify_deferred
    @log << :notified
  end
end

# -----------------------------------------------------------------------

class TestEvent < Minitest::Test

  # notify で wait 中の Fiber が起床する
  def test_notify_wakes_waiter
    event   = DeepSveite::Event.new
    waiter  = EventWaiter.new
    notifier = EventNotifier.new
    waiter.reader  = event.reader
    notifier.writer = event.writer

    tb = DeepSveite::TestBench.new
    tb.instance_variable_set(:@event,    event)
    tb.instance_variable_set(:@waiter,   waiter)   # 先に登録 → 先に wait
    tb.instance_variable_set(:@notifier, notifier)

    sim = DeepSveite::Simulator.new(tb)
    sim.build
    sim.run

    assert_equal [:woken],    waiter.log
    assert_equal [:notified], notifier.log
  end

  # notify_deferred で wait 中の Fiber が次クロックで起床する
  def test_notify_deferred_wakes_waiter
    event    = DeepSveite::Event.new
    waiter   = EventWaiter.new
    notifier = EventNotifierDeferred.new
    waiter.reader   = event.reader
    notifier.writer = event.writer

    tb = DeepSveite::TestBench.new
    tb.instance_variable_set(:@event,    event)
    tb.instance_variable_set(:@waiter,   waiter)
    tb.instance_variable_set(:@notifier, notifier)

    sim = DeepSveite::Simulator.new(tb)
    sim.build
    sim.run

    assert_equal [:woken],    waiter.log
    assert_equal [:notified], notifier.log
  end

  # 同じ Event を wait している複数の Fiber が全て起床する
  def test_notify_wakes_all_waiters
    event    = DeepSveite::Event.new
    waiter1  = EventWaiter.new
    waiter2  = EventWaiter.new
    notifier = EventNotifier.new
    waiter1.reader  = event.reader
    waiter2.reader  = event.reader
    notifier.writer = event.writer

    tb = DeepSveite::TestBench.new
    tb.instance_variable_set(:@event,    event)
    tb.instance_variable_set(:@waiter1,  waiter1)
    tb.instance_variable_set(:@waiter2,  waiter2)
    tb.instance_variable_set(:@notifier, notifier)

    sim = DeepSveite::Simulator.new(tb)
    sim.build
    sim.run

    assert_equal [:woken], waiter1.log
    assert_equal [:woken], waiter2.log
  end

  # OR: event_a または event_b のどちらかで起床する（a のみ発火）
  def test_or_wakes_on_first_event
    event_a  = DeepSveite::Event.new
    event_b  = DeepSveite::Event.new

    waiter = DeepSveite::Module.new.tap do |m|
      m.instance_variable_set(:@log, [])
      m.define_singleton_method(:log) { @log }
      m.define_singleton_method(:reader_a=) { |r| @reader_a = r }
      m.define_singleton_method(:reader_b=) { |r| @reader_b = r }
    end

    # OR 待機 + a のみ notify するシンプルな構成を直接クラスで表現
    class << (or_waiter = DeepSveite::Module.new)
      attr_accessor :reader_a, :reader_b
      attr_reader :log
      def initialize_log; @log = []; end
    end
    or_waiter.initialize_log

    # シンプルな専用クラスで書き直す
    or_waiter_mod  = Class.new(DeepSveite::Module) do
      attr_accessor :reader_a, :reader_b
      attr_reader   :log
      def initialize; @log = []; super(); end
      process :run
      def run
        (@reader_a | @reader_b).wait
        @log << :woken
      end
    end.new

    notifier_a_mod = Class.new(DeepSveite::Module) do
      attr_accessor :writer
      process :run
      def run; @writer.notify; end
    end.new

    or_waiter_mod.reader_a  = event_a.reader
    or_waiter_mod.reader_b  = event_b.reader
    notifier_a_mod.writer   = event_a.writer

    tb = DeepSveite::TestBench.new
    tb.instance_variable_set(:@event_a,       event_a)
    tb.instance_variable_set(:@event_b,       event_b)
    tb.instance_variable_set(:@or_waiter,     or_waiter_mod)
    tb.instance_variable_set(:@notifier_a,    notifier_a_mod)

    sim = DeepSveite::Simulator.new(tb)
    sim.build
    sim.run

    assert_equal [:woken], or_waiter_mod.log
  end

  # AND: event_a と event_b の両方が発火して初めて起床する
  def test_and_wakes_when_both_fired
    event_a = DeepSveite::Event.new
    event_b = DeepSveite::Event.new

    and_waiter_mod = Class.new(DeepSveite::Module) do
      attr_accessor :reader_a, :reader_b
      attr_reader   :log
      def initialize; @log = []; super(); end
      process :run
      def run
        (@reader_a & @reader_b).wait
        @log << :woken
      end
    end.new

    notifier_ab_mod = Class.new(DeepSveite::Module) do
      attr_accessor :writer_a, :writer_b
      process :run
      def run
        @writer_a.notify
        @writer_b.notify
      end
    end.new

    and_waiter_mod.reader_a   = event_a.reader
    and_waiter_mod.reader_b   = event_b.reader
    notifier_ab_mod.writer_a  = event_a.writer
    notifier_ab_mod.writer_b  = event_b.writer

    tb = DeepSveite::TestBench.new
    tb.instance_variable_set(:@event_a,       event_a)
    tb.instance_variable_set(:@event_b,       event_b)
    tb.instance_variable_set(:@and_waiter,    and_waiter_mod)
    tb.instance_variable_set(:@notifier_ab,   notifier_ab_mod)

    sim = DeepSveite::Simulator.new(tb)
    sim.build
    sim.run

    assert_equal [:woken], and_waiter_mod.log
  end

  # AND: 片方だけ発火しても起床しない
  def test_and_does_not_wake_on_single_event
    event_a = DeepSveite::Event.new
    event_b = DeepSveite::Event.new

    and_waiter_mod = Class.new(DeepSveite::Module) do
      attr_accessor :reader_a, :reader_b
      attr_reader   :log
      def initialize; @log = []; super(); end
      process :run
      def run
        (@reader_a & @reader_b).wait
        @log << :woken
      end
    end.new

    notifier_a_only = Class.new(DeepSveite::Module) do
      attr_accessor :writer_a
      process :run
      def run; @writer_a.notify; end
    end.new

    and_waiter_mod.reader_a    = event_a.reader
    and_waiter_mod.reader_b    = event_b.reader
    notifier_a_only.writer_a   = event_a.writer

    tb = DeepSveite::TestBench.new
    tb.instance_variable_set(:@event_a,        event_a)
    tb.instance_variable_set(:@event_b,        event_b)
    tb.instance_variable_set(:@and_waiter,     and_waiter_mod)
    tb.instance_variable_set(:@notifier_a,     notifier_a_only)

    sim = DeepSveite::Simulator.new(tb)
    sim.build
    sim.run

    assert_equal [], and_waiter_mod.log
  end
end
