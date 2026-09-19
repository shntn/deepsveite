# DeepSveite

Ruby で書かれた軽量な RTL / TLM ハードウェアシミュレーションフレームワークです。
SystemC / SystemVerilog のエッセンスを参考に、Ruby のシンプルな記述でハードウェア動作をモデリングできます。

API の詳細は [docs/api.md](docs/api.md) を参照してください。

---

## 特徴

- **RTL シミュレーション** — Wire / Reg、always_comb / always_ff、デルタサイクル収束、NBA（Non-Blocking Assignment）
- **TLM シミュレーション** — Socket / FIFO / Event、Ruby Fiber による `process` / `wait`
- **RTL / TLM 協調シミュレーション** — Wire 経由の信号でモデル間を接続
- **ビットセレクト** — `signal[n]` / `signal[lo..hi]` による単ビット・範囲アクセス
- **配列信号** — `RegArray` / `WireArray` によるメモリ・ルックアップテーブル
- **VCD 出力** — 1行追加するだけで全信号を階層付きで記録・出力

---

## 概要

### 想定用途

- RTL設計の動作検証・プロトタイピング（Verilator / SystemC を用意せずRubyだけで動かす）
- TLMによるアーキテクチャ探索・高抽象度モデリング
- RTL / TLM協調シミュレーション（CPUコアとメモリモデルを同一シミュレータ上で動かすなど）

### RTL シミュレーション

クロック駆動のシミュレーション層です。`always_comb` / `always_ff` でHDLと同様の記述スタイルを使えます。delta cycle収束により組み合わせ回路の多段伝播を自動で処理します。

使用できる信号:

- **Wire** — 組み合わせ信号。`always_comb` の出力。書き込みは更新イベントとして Active 領域で反映
- **Reg** — 順序信号。Non-Blocking Assignment（NBA）で、Active 領域が空になった後の NBA 領域で確定

評価イベント（`always_comb` / `always_ff` の実行）と更新イベント（信号値の反映）を Active / NBA の 2 つの領域で処理する、SystemVerilog と同様のスケジューリングです。Reg の更新に反応する `always_comb` も、同じ `sim.step` 内で収束します。

### TLM シミュレーション

クロックを抽象化したシミュレーション層です。RubyのFiberを利用して `process` / `wait` を自然に記述できます。

使用できる通信オブジェクト:

- **Socket** — ターゲット / イニシエータ間のトランザクション呼び出し
- **FIFO** — プロデューサ / コンシューマ間のキュー（満杯 / 空でブロック）
- **Event** — プロセス間の同期通知（即時・遅延・OR・AND）

### VCD 記録

RTL信号・TLM信号（FIFO / Event / Socket）を同一波形ビューアで確認できます。Eventの即時通知（`notify`）と遅延通知（`notify_deferred`）の違いも波形上で観察できます。`sim.build` 後に `VCD.new` を1行追加するだけで全信号を自動収集し、モジュール階層をVCDスコープに反映します。

---

## 動作環境

- Ruby 3.0 以上（endless method 構文を使用）

---

## インストール

### リポジトリをそのまま使う

```bash
git clone https://github.com/shntn/DeepSveite.git
```

コード内では `require_relative` でロードします。

```ruby
require_relative "path/to/DeepSveite/lib/deepsveite"
```

### gem としてインストールする

リポジトリから gem をビルドしてローカルにインストールします。

```bash
git clone https://github.com/shntn/DeepSveite.git
cd DeepSveite
gem build deepsveite.gemspec
gem install deepsveite-0.2.0.gem
```

インストール後は `require` だけで使えます。

```ruby
require "deepsveite"
```

### Gemfile に記載する

Bundler を使う場合は `Gemfile` に以下を追加します。

```ruby
# GitHub から直接
gem "deepsveite", github: "shntn/DeepSveite"

# ローカルパスから
gem "deepsveite", path: "path/to/DeepSveite"
```

---

## クイックスタート

```ruby
require_relative "lib/deepsveite"
DS = DeepSveite

class Counter < DS::Module
  attr_accessor :clk
  always_ff :tick, cond: [:clk.posedge]

  def initialize
    @count = DS::Reg.new(width: 4)
    super()
  end

  def count = @count

  def tick
    @count.r = @count.r + 1
  end
end

class Bench < DS::TestBench
  attr_accessor :clk
  attr_reader   :counter
  def initialize
    super()
    @clk     = DS::Wire.new
    @counter = Counter.new
    @counter.clk = @clk.in
  end
end

tb  = Bench.new
sim = DS::Simulator.new(tb, tb.clk)
sim.build

6.times do
  sim.step
  puts tb.counter.count.r if tb.clk.w == 1
end
```

---

## RTL シミュレーション

### Wire / Reg

Wire と Reg はシミュレーション内で使います。
`w=` は更新イベント（Active 領域）、`r=` はノンブロッキング代入（NBA 領域）として反映されます。
TestBench レベルの Wire / Reg に `sim.step` の前に設定した値は、そのステップのクロック変化と同時に反映されます。

```ruby
class SigBench < DS::TestBench
  attr_reader :sig, :reg

  def initialize
    super()
    @sig = DS::Wire.new(width: 8)  # 8ビット Wire
    @reg = DS::Reg.new(width: 4)   # 4ビット Reg
  end
end

tb  = SigBench.new
sim = DS::Simulator.new(tb)
sim.build

# build 後: 初期値 0
puts tb.sig.w   # => 0
puts tb.reg.r   # => 0

# 書き込み → step で更新イベントが反映され値が確定
tb.sig.w = 0xFF
sim.step
puts tb.sig.w   # => 255

# ビットセレクト
tb.sig.w = 0b10101010   # ビット 1, 3, 5, 7 をセット
sim.step
puts tb.sig[1]           # => 1
puts tb.sig[4..7]        # => 10 (0b1010)
```

### always\_comb / always\_ff

```ruby
class MyModule < DS::Module
  always_comb :calc, reads: [:a, :b]   # a または b が変化したら起動
  always_ff   :latch, cond: [:clk.posedge]

  def calc
    @result.w = @a.w + @b.w
  end

  def latch
    @reg.r = @din.w if @load.w == 1
  end
end
```

### ポート（in / out）

```ruby
mod.din  = wire.in   # 入力ポート（書き込み不可）
mod.dout = wire.out  # 出力ポート（読み出し不可）
```

---

## 配列信号

### RegArray

複数要素を持つ順序信号の配列です。シンクロナス RAM やレジスタファイルのモデルに使います。
`always_ff` などの RTL プロセス内での `[]=` はノンブロッキング代入（NBA）で、同じクロックエッジで読み出すと更新前の値が返ります。
`process`（TLM）・TestBench・`initialize` など RTL プロセス外での `[]=` は即時に反映されます。
VCD には `mem[0]`, `mem[1]` ... として出力されます。
ビットセレクトは、インデックスの後ろにビット位置または範囲を渡します（`mem[i, 3]`、`mem[i, 0..3] = 0xF`）。WireArray でも同じです。

```ruby
class SyncRAM < DS::Module
  attr_accessor :clk, :we, :addr, :din
  attr_reader   :dout
  always_ff :tick, cond: [:clk.posedge]

  def initialize
    @mem  = DS::RegArray.new(width: 8, size: 256)
    @clk  = DS::Wire.new
    @we   = DS::Wire.new
    @addr = DS::Wire.new(width: 8)
    @din  = DS::Wire.new(width: 8)
    @dout = DS::Reg.new(width: 8)
    super()
  end

  def tick
    @mem[@addr.w] = @din.w if @we.w == 1
    @dout.r = @mem[@addr.w]
  end
end

# TestBench レベルで Wire を定義してポート接続する
class RAMBench < DS::TestBench
  attr_reader :clk, :we, :addr, :din, :ram

  def initialize
    super()
    @clk  = DS::Wire.new
    @we   = DS::Wire.new
    @addr = DS::Wire.new(width: 8)
    @din  = DS::Wire.new(width: 8)
    @ram  = SyncRAM.new
    @ram.clk  = @clk.in
    @ram.we   = @we.in
    @ram.addr = @addr.in
    @ram.din  = @din.in
  end
end
```

### WireArray

複数要素を持つ組み合わせ信号の配列です。ルックアップテーブルや定数パレットに使います。

```ruby
class PaletteLUT < DS::Module
  attr_accessor :sel
  attr_reader   :out
  always_comb :lookup

  TABLE = [0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00]

  def initialize
    @lut = DS::WireArray.new(width: 24, size: TABLE.size)
    @sel = DS::Wire.new(width: 2)
    @out = DS::Wire.new(width: 24)
    TABLE.each_with_index { |v, i| @lut[i] = v }
    super()
  end

  def lookup
    @out.w = @lut[@sel.w]
  end
end
```

---

## TLM シミュレーション

### process / wait

```ruby
class Sender < DS::Module
  process :run

  def run
    3.times do |i|
      puts "send #{i}"
      wait   # 1 クロックサイクル待機
    end
  end
end
```

### Socket

トランザクションのフィールドは `DS::Payload` サブクラスで定義します。
ビット幅（`width:`）と enum マッピング（`enum:`）をここに集約することで、
VCD 記録も自動化されます。

```ruby
# Payload 定義（フィールド・ビット幅・enum を一元管理）
class MemPayload < DS::Payload
  field :cmd,    width: 1,  enum: { READ: 0, WRITE: 1 }
  field :addr,   width: 16
  field :data,   width: 8
  field :status, width: 1,  enum: { OK: 0, ERROR: 1 }
end

# ターゲット
class Memory < DS::Module
  attr_accessor :mem_socket
  def initialize
    @mem_socket = DS::Socket.new(method: :b_transport, payload: MemPayload)
    super()
  end

  def b_transport(payload)  # payload は MemPayload インスタンス（in-place 変更）
    payload.data   = @mem.fetch(payload.addr, 0xFF) if payload.cmd == :READ
    payload.status = :OK
  end
end

# イニシエータ
class CPU < DS::Module
  attr_accessor :mem_socket
  process :run

  def run
    @mem_socket.b_transport(cmd: :WRITE, addr: 0x100, data: 0xAB)
    r = @mem_socket.b_transport(cmd: :READ, addr: 0x100)
    puts "read: 0x#{r.data.to_s(16)}"
  end
end

# 接続
cpu.mem_socket.bind(memory.mem_socket)
```

### FIFO

```ruby
# 書き込みは次クロックで読み出し可能
fifo   = DS::FIFO.new
writer = fifo.writer   # FIFOWriter
reader = fifo.reader   # FIFOReader

# Writer 側
writer.write(42)

# Reader 側（データが来るまでブロック）
value = reader.read
```

### Event

```ruby
event  = DS::Event.new
writer = event.writer
reader = event.reader

# 待機
reader.wait              # イベントを待つ

# 通知
writer.notify            # 即時通知
writer.notify_deferred   # 次クロックで通知

# OR / AND
(event_a.reader | event_b.reader).wait   # どちらかで起床
(event_a.reader & event_b.reader).wait   # 両方で起床
```

---

## RTL / TLM 協調シミュレーション

TLM は negedge で動作し、RTL は posedge で動作します。
`wait` 1回 = 1 RTL クロックサイクル（posedge での取り込み + NBA 完了）に対応します。

```ruby
# TLM → RTL: Wire に書き込んで RTL に伝える
def run
  @data_in.w = 0x42
  @load.w    = 1
  wait                         # posedge で RTL が取り込み、NBA 確定まで待機
  puts @reg_module.result.r    # NBA 反映済みの値を読む
  @load.w = 0
end

# RTL → TLM: RTL の出力を TLM が毎クロック読む
def watch
  loop do
    val = @counter.count.r
    puts "count = #{val}"
    break if val >= 10
    wait
  end
end
```

---

## VCD 出力

`sim.build` の後に `VCD.new` を 1行追加するだけで、全信号を階層付きで記録できます。
`VCD` を使用しない場合はシミュレーションに一切オーバーヘッドはありません。

```ruby
sim.build
vcd = DS::VCD.new(sim, filename: "dump.vcd")   # ← この1行だけ追加

sim.run { n >= 100 }

vcd.write   # VCD ファイルを出力
```

出力される VCD はモジュール階層と配列要素を自動で反映します：

```
$scope module Bench $end
  $var wire 1 ! clk $end
  $scope module ram $end
    $var reg 8 " dout $end
    $var reg 8 # mem[0] $end
    $var reg 8 $ mem[1] $end
    $var reg 8 % mem[2] $end
  $upscope $end
$upscope $end
```

---

## サンプル一覧

| ファイル | 内容 |
|---|---|
| `examples/ex_wire.rb` | Wire と always\_comb の基本 |
| `examples/ex_reg.rb` | Reg と always\_ff（カウンタ） |
| `examples/ex_bitselect.rb` | ビットセレクト / パートセレクト |
| `examples/ex_array.rb` | RegArray（シンクロナス RAM）/ WireArray（パレットLUT） |
| `examples/ex_socket.rb` | TLM Socket（CPU ↔ メモリ） |
| `examples/ex_socket_vcd.rb` | TLM Socket VCD 出力（Payload フィールド波形記録） |
| `examples/ex_fifo.rb` | TLM FIFO（1クロック遅延） |
| `examples/ex_event.rb` | TLM Event（即時・遅延・OR・AND） |
| `examples/ex_rtl_tlm.rb` | RTL / TLM 協調シミュレーション |
| `examples/ex_vcd.rb` | VCD 出力（4ビットカウンタ） |
| `examples/ex_sap1.rb` | SAP-1（Simple As Possible CPU）完全実装 |

---

## テスト実行

```bash
ruby tests/wire.rb
ruby tests/reg.rb
ruby tests/module.rb
ruby tests/sequential.rb
ruby tests/socket.rb
ruby tests/fifo.rb
ruby tests/event.rb
ruby tests/vcd.rb
ruby tests/array.rb
ruby tests/multidriver.rb
ruby tests/scheduler.rb
ruby tests/scheduler_edge.rb
ruby tests/cosim.rb
ruby tests/mask.rb
ruby tests/multidriver_array.rb
ruby tests/vcd_timing.rb
ruby tests/examples.rb
```

まとめて実行する場合は `rake test` を使います。

---

## アーキテクチャ

### シミュレーションループ

```
sim.step の実行順序:
  1. クロックトグル            ← TestBench で設定した信号とともに更新イベントとして登録
  2. _rtl_cycle
       ├─ Active 領域        ← 更新イベントを反映 → 感度のある評価イベント
       │                       （always_comb / always_ff）を実行、空になるまで繰り返し
       ├─ NBA 領域           ← Reg の更新を反映 → 感度のある評価イベントを Active へ
       └─ Active / NBA が両方空になるまで繰り返し、多重ドライバを検査
  3. _tlm_cycle                ← TLM process の Fiber 再開（negedge）
  4. _clock_notification_phase
       └─ TLM クロック通知   ← posedge 時のみ pending Fiber を tlm_queue へ
```

Wire の `w=` は Active の更新イベント、Reg の `r=` は NBA の更新イベントとして登録されます。
エッジ（`posedge` / `negedge`）は信号の値が変化した更新イベントの時点で判定し、該当する `always_ff` を評価イベントとして登録します。

### ファイル構成

```
lib/deepsveite/
  signal.rb             基底クラス
  wire.rb               Wire（組み合わせ信号）
  reg.rb                Reg（順序信号・NBA）
  wirearray.rb          WireArray（Wire の配列）
  regarray.rb           RegArray（Reg の配列）
  module.rb             Module 基底（always_comb / always_ff / process / wait）
  testbench.rb          TestBench 基底
  payload.rb            TLM Payload（フィールド定義・enum・VCD幅）
  socket.rb             TLM Socket
  fifo.rb               TLM FIFO
  event.rb              TLM Event / EventOrReader / EventAndReader / Latch
  environmentbuilder.rb 階層構造の自動構築・信号登録
  simulator.rb          シミュレーションループ
  vcd.rb                VCD 出力
```
