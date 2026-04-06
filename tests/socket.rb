# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/deepsveite"

DS = DeepSveite

# KV ストアのペイロード定義
class KVPayload < DS::Payload
  field :cmd,    width: 1,  enum: { write: 0, read: 1 }
  field :key,    width: 32
  field :value,  width: 32
  field :status, width: 1,  enum: { ok: 0, error: 1 }
end

# キー・バリュー ストア（ターゲット側モジュール）
# Socket にメソッド名を登録し、イニシエータからの呼び出しを受け付ける
class KVStore < DS::Module
  attr_accessor :socket

  def initialize
    @socket = DS::Socket.new(method: :transaction, payload: KVPayload)
    @store  = {}
    super()
  end

  def transaction(payload)
    case payload.cmd
    when :write
      @store[payload.key] = payload.value
      payload.status = :ok
    when :read
      payload.value  = @store[payload.key]
      payload.status = :ok
    end
  end
end

# クライアント（イニシエータ側モジュール）
# bind した先の Socket のメソッドを呼び出す
class KVClient < DS::Module
  attr_accessor :socket
  attr_reader   :results

  def initialize(&run_block)
    @socket    = DS::Socket.new
    @results   = []
    @run_block = run_block
    super()
  end

  process :run
  def run = @run_block.call(self)
end

class KVBench < DS::TestBench
  attr_reader :store, :client

  def initialize(&client_block)
    super()
    @store  = KVStore.new
    @client = KVClient.new(&client_block)
    @client.socket.bind(@store.socket)
  end
end

# -----------------------------------------------------------------------

class TestSocket < Minitest::Test

  # write した値を read で取り出せる
  def test_write_and_read
    tb = KVBench.new do |c|
      c.socket.transaction(cmd: :write, key: :x, value: 42)
      r = c.socket.transaction(cmd: :read, key: :x)
      c.results << r.value
    end
    sim = DS::Simulator.new(tb)
    sim.build
    sim.run

    assert_equal 42, tb.client.results.first
  end

  # 書き込んでいないキーは nil を返す
  def test_unwritten_key_returns_nil
    tb = KVBench.new do |c|
      r = c.socket.transaction(cmd: :read, key: :missing)
      c.results << r.value
    end
    sim = DS::Simulator.new(tb)
    sim.build
    sim.run

    assert_nil tb.client.results.first
  end

  # ターゲットが設定した status がイニシエータに届く
  def test_return_value
    tb = KVBench.new do |c|
      r = c.socket.transaction(cmd: :write, key: :a, value: 99)
      c.results << r.status
    end
    sim = DS::Simulator.new(tb)
    sim.build
    sim.run

    assert_equal :ok, tb.client.results.first
  end

  # 複数トランザクションを順番に実行できる
  def test_multiple_transactions
    tb = KVBench.new do |c|
      c.socket.transaction(cmd: :write, key: :a, value: 1)
      c.socket.transaction(cmd: :write, key: :b, value: 2)
      c.socket.transaction(cmd: :write, key: :c, value: 3)
      [:a, :b, :c].each do |k|
        r = c.socket.transaction(cmd: :read, key: k)
        c.results << r.value
      end
    end
    sim = DS::Simulator.new(tb)
    sim.build
    sim.run

    assert_equal [1, 2, 3], tb.client.results
  end

  # 後から write した値で上書きされる
  def test_overwrite
    tb = KVBench.new do |c|
      c.socket.transaction(cmd: :write, key: :x, value: 10)
      c.socket.transaction(cmd: :write, key: :x, value: 20)
      r = c.socket.transaction(cmd: :read, key: :x)
      c.results << r.value
    end
    sim = DS::Simulator.new(tb)
    sim.build
    sim.run

    assert_equal 20, tb.client.results.first
  end

  # bind していないメソッド名を呼び出すと NoMethodError になる
  def test_undefined_method_raises
    tb = KVBench.new do |c|
      c.results << :not_called
    end
    sim = DS::Simulator.new(tb)
    sim.build

    assert_raises(NoMethodError) do
      tb.client.socket.unknown_method(cmd: :read, key: :x)
    end
  end
end
