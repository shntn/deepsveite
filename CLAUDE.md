# DeepSveite

DeepSveite は Ruby 製の RTL/TLM ハードウェアシミュレータ。
SystemC/SystemVerilog 相当のシミュレーションを純 Ruby で実現する。
信号は `X`, `Z` 状態のシミュレーションに非対応。

3 つの抽象レベルが共存する:
- RTL — クロック駆動、`always_comb`/`always_ff`、デルタサイクル収束、NBA
- TLM — クロック抽象、Fiber ベースの `process`/`wait`、Socket/FIFO/Event 通信
- RTL/TLM 協調シミュレーション — RTL/TLM 間は Wire で通信を行う

## SystemC Mapping

RTL レベルは **SystemVerilog** に、TLM レベルは **SystemC / TLM-2.0** に対応する。

### RTL（SystemVerilog 対応）

| SystemVerilog              | DeepSveite                                |
|----------------------------|-------------------------------------------|
| `wire` / `logic`           | `Wire`                                    |
| `reg` / `logic`            | `Reg`                                     |
| `wire [N:0] arr [0:M-1]`   | `WireArray`                               |
| `reg [N:0] arr [0:M-1]`    | `RegArray`                                |
| `always_comb`              | `always_comb`                             |
| `always_ff @(posedge clk)` | `always_ff :method, cond: [:clk.posedge]` |
| ノンブロッキング代入 `<=`  | `r =`（Reg への代入）                     |

### TLM（SystemC / TLM-2.0 対応）

| SystemC / TLM-2.0                         | DeepSveite                    |
|-------------------------------------------|-------------------------------|
| `sc_module`                               | `DeepSveite::Module`          |
| `SC_THREAD` + `wait()`                    | `process` + `wait`            |
| `sc_fifo<T>`                              | `FIFO`                        |
| `sc_event`                                | `Event`                       |
| TLM-2.0 initiator/target socket + payload | `Socket` + `Payload`          |
| `sc_main` / `sc_start`                    | `TestBench` / `Simulator#run` |

DeepSveite 固有の相違点:
- `Module#initialize` ではインスタンス変数の設定を終えてから末尾で `super()` を呼ぶ（`super()` 内で登録処理が走る）
- Wire / Reg を Module 間で接続するときは `.in` / `.out` でポートビューに変換して渡す
- `SC_NS` 等の物理時間単位はない


## Core Concepts

### RTL Signals

* Wire — 組合せ信号。RTL レベルのモジュールと TLM レベルのモジュールの接続にも使用される。
  RTL レベルでは `always_comb` で算出する。

* Reg — 順序回路信号。`always_ff` で算出する。always_ff ではノンブロッキング代入。

* WireArray - 組み合わせ信号の配列定義

* RegArray - 順序回路信号

### TLM Signals

* Socket - イニシエータからターゲットにトランザクション(データ)を渡すと共に制御を移す。
  ターゲットは受信したトランザクションを元に処理を行い結果をトランザクションに格納。
  処理結果を格納したトランザクションをイニシエータに移す。

* FIFO - FIFO。

* Event - 同期処理に使用する。即時イベントと非同期イベントがある

* Payload - Socket のトランザクションを定義するためのクラス

### Structure

* Module - SystemVerilog の Module に相当する。ネスト定義に対応

* always_comb - Module 内で宣言して使用する。組み合わせ回路のメソッドを指定する

* always_ff - Module 内で宣言して使用する。順序回路のメソッドを指定する。ノンブロッキング代入

* TestBench - シミュレーション対象のモジュールと入出力する信号を宣言する

* Simulator - シミュレーションを実行するクラス

* VCD - 信号変化を自動で収集、記録する。

## API・サンプル

- API リファレンス（各クラスのメソッド、シミュレーションのスケジューリングの詳細）: [docs/api.md](docs/api.md)
- 動作するサンプル: `examples/ex_*.rb`（`tests/examples.rb` で実行確認している）
- 使い方の例は CLAUDE.md に書かず `examples/` に追加し、`tests/examples.rb` の `EXPECTATIONS` に登録する

## RTL/TLM Co-simulation

RTL モジュールと TLM モジュールは **Wire** を橋渡しとして通信する。

- TLM の `process` から Wire に書き込むと、次の `sim.step` で RTL 側に伝搬する
- RTL の `always_ff` / `always_comb` が出力した Wire の値を、TLM の `process` から読み取れる
- 混在構成では `sim.run { halt_condition }` を使い、RTL と TLM を同一タイムステップで進める

サンプルは `examples/ex_rtl_tlm.rb`、テストは `tests/cosim.rb`。

## Conventions & Rules

### シミュレーションのスケジューリング

RTL は Active / NBA の 2 領域で処理する（詳細と表は [docs/api.md](docs/api.md)）。

- `sim.build` の最後（時刻 0）に、すべての `always_comb` を 1 回評価して収束させる（SystemVerilog と同様）
- `Wire#w=` は更新イベント（Active）
- `Reg#r=` は NBA。`always_ff` がクロックエッジで読む値は、そのエッジ直前の値
- `WireArray` / `RegArray` の `[]=` は、RTL プロセス内では更新イベント / NBA、プロセス外（TLM / TestBench / `initialize`）では即時反映
- 書き込んだ値は `width` でマスクされる（負数は 2 の補数、`true` / `false` は 1 / 0）
- 別々のプロセスが同じ信号を駆動すると多重ドライバのエラーになる
- 配列の範囲外インデックスは `IndexError`

### テスト

`rake test` で `tests/*.rb` をすべて実行する。

### Module / TestBench の initialize では super() を末尾で呼ぶ

`Module` および `TestBench` のサブクラスの `initialize` では、すべてのインスタンス変数を設定してから `super()` を末尾で呼ぶ。
`super()` の内部でプロセス・信号の登録が行われるため、順序が逆になるとエラーになる。

```ruby
class MyModule < DeepSveite::Module
  def initialize
    @clk   = DeepSveite::Wire.new    # 先に変数を設定
    @count = DeepSveite::Reg.new(width: 8)
    super()                           # 必ず末尾
  end
end

class Bench < DeepSveite::TestBench
  def initialize
    @clk = DeepSveite::Wire.new
    @dut = MyModule.new
    super()                           # 必ず末尾
  end
end
```

### vcd_signal はクラス本体で宣言する

`vcd_signal` はクラス本体（`def initialize` の外）で宣言する。`initialize` 内では宣言できない。

```ruby
class MyModule < DeepSveite::Module
  vcd_signal :count, width: 8   # クラス本体で宣言
  process :run

  def initialize
    @count = 0
    super()
  end
end
```

### Wire / Reg のポート接続

Module 間で信号を渡すときは、TestBench 側の Wire / Reg を `.in` / `.out` でポートビューに変換してから渡す。

```ruby
# TestBench 側
@dut.clk = @clk.in     # 受信ポートとして渡す
@dut.out = @out.out    # 送信ポートとして渡す
```

Module コンストラクタの引数で受け取る場合も同様。

```ruby
class Adder < DeepSveite::Module
  def initialize(a, b, result)
    @a      = a.in       # ポートビューとして保持
    @b      = b.in
    @result = result.out
    super()
  end
end
```

