# DeepSveite API リファレンス

概要は [README.md](../README.md)、動作するサンプルは [examples/](../examples/) を参照。

## Wire

* `new(init: 0, width: 1) -> Wire`

  ビット長 1、初期値 0 の組み合わせ回路の信号を初期化して返す。

  ```
  signal = Wire.new                 # 初期値 0、ビット長 1 の組み合わせ回路の信号を返す
  sub_signal = Wire.new(width: 8)   # 初期値 0、ビット長 8 の組み合わせ回路の信号を返す
  ```

* `in -> Wire`

  組み合わせ回路信号の受信用インスタンスを返す。
  モジュール間の信号送受信に使用する。

  ```
  foo = Wire.new
  bar = foo.in
  ```

* `out -> Wire`

  組み合わせ回路信号の送信用インスタンスを返す。
  モジュール間の信号送受信に使用する。

  ```
  foo = Wire.new
  bar = foo.out
  ```

* `w -> val`

  組み合わせ回路に設定されている値を返す

  ```
  foo = Wire.new
  foo.w = 3
  bar = foo.w
  ```

* `w = val`

  組み合わせ回路に val の値を設定する。
  値は更新イベント（Active 領域）として反映されるため、同じプロセス内で書いた直後に `w` を読むと書く前の値が返る。
  詳細は「シミュレーションのスケジューリング」を参照。

  ```
  foo = Wire.new(width: 8)
  foo.w = 5
  ```

* `w[nth] -> val`

  組み合わせ回路の nth 番目のビットの値を返す

  ```
  foo = Wire.new(width: 8)
  foo.w = 0x55
  bar = foo[2]              # bar == 1
  ```

* `w[nth] = val`

  組み合わせ回路の nth 番目のビットに値を設定する

  ```
  foo = Wire.new(width: 8)
  foo.w = 0
  foo[1] = 1                # foo == 2
  ```

* `w[range] -> val`

  Range オブジェクト range 範囲にある組み合わせ回路のビットを返す

  ```
  foo = Wire.new(width: 8)
  foo.w = 0x55
  bar = foo[1..2]           # bar = 2
  ```

* `w[range] = val`

  Range オブジェクト range 範囲にある組み合わせ回路のビットに値を設定する

  ```
  foo = Wire.new(width: 8)
  foo.w = 0x55
  foo[0..3] = 0             # foo = 0x50
  ```

## Reg

* `new(width: 1) -> Reg`

  ビット長 1 の順序回路の信号を初期化して返す。

  ```
  reg = Reg.new            # ビット長 1
  reg = Reg.new(width: 8)  # ビット長 8
  ```

* `in -> Reg`

  順序回路信号の受信用インスタンスを返す。
  モジュール間の信号送受信に使用する。

  ```
  foo = Reg.new
  bar = foo.in
  ```

* `out -> Reg`

  順序回路信号の送信用インスタンスを返す。
  モジュール間の信号送受信に使用する。

  ```
  foo = Reg.new
  bar = foo.out
  ```

* `r -> val`

  順序回路に確定している値を返す。

  ```
  reg = Reg.new(width: 8)
  val = reg.r   # => 0
  ```

* `r = val`

  ノンブロッキング代入。NBA 領域（Active 領域が空になった後）で `r` に確定する。

  ```
  reg.r = 42
  ```

* `r[nth] -> val`

  nth 番目のビットの値を返す。

  ```
  reg = Reg.new(width: 8)
  reg.r = 0x55
  val = reg[1]   # => 0
  ```

* `r[nth] = val`

  nth 番目のビットにノンブロッキング代入する。

  ```
  reg = Reg.new(width: 8)
  reg[0] = 1
  ```

* `r[range] -> val`

  Range 範囲のビットを返す。

  ```
  reg = Reg.new(width: 8)
  reg.r = 0x55
  val = reg[4..7]   # => 5
  ```

* `r[range] = val`

  Range 範囲のビットにノンブロッキング代入する。

  ```
  reg = Reg.new(width: 8)
  reg[0..3] = 0xF
  ```

## WireArray

* `new(width: 1, size: 1) -> WireArray`

  ビット長 `width`、要素数 `size` の組み合わせ信号配列を返す。

  ```
  lut = WireArray.new(width: 24, size: 8)
  ```

* `[index] -> val`

  index 番目の要素の値を返す。範囲外の index（負数を含む）は `IndexError` になる。

  ```
  lut = WireArray.new(width: 8, size: 4)
  lut[0] = 0xFF
  val = lut[0]   # => 255
  ```

* `[index] = val`

  index 番目の要素に値を設定する。
  `always_comb` / `always_ff` の中では Wire と同じく更新イベント経由で反映される。
  `initialize` / `process` / TestBench など RTL プロセスの外では即時に反映される。

  ```
  lut = WireArray.new(width: 8, size: 4)
  lut[2] = 0xAB
  ```

## RegArray

* `new(width: 1, size: 1) -> RegArray`

  ビット長 `width`、要素数 `size` の順序回路信号配列を返す。

  ```
  mem = RegArray.new(width: 8, size: 256)
  ```

* `[index] -> val`

  index 番目の要素の値を返す。範囲外の index（負数を含む）は `IndexError` になる。

  ```
  mem = RegArray.new(width: 8, size: 4)
  mem[0] = 42
  val = mem[0]   # => 42
  ```

* `[index] = val`

  index 番目の要素に値を設定する。
  `always_ff` などの RTL プロセスの中ではノンブロッキング代入（NBA）となり、同じクロックエッジで読み出すと更新前の値が返る。
  `process` / TestBench など RTL プロセスの外では即時に反映される。

  ```
  mem = RegArray.new(width: 8, size: 4)
  mem[3] = 0xFF
  ```

## Socket

* `new(method: nil, payload: nil) -> Socket`

  Socket を初期化して返す。
  `method:` はターゲット側のハンドラメソッド名（Symbol）。
  `payload:` は `Payload` サブクラス。イニシエータ側は両方 `nil`。

  ```
  # ターゲット側
  socket = Socket.new(method: :b_transport, payload: MyPayload)

  # イニシエータ側
  socket = Socket.new
  ```

* `bind(target_socket)`

  イニシエータ側の Socket をターゲット側の Socket に接続する。

  ```
  initiator_socket.bind(target_socket)
  ```

* `<method_name>(**kwargs) -> Payload`

  ターゲット側のハンドラメソッド名で呼び出す。
  kwargs は Payload のフィールドに対応する。戻り値は処理後の Payload インスタンス。
  呼び出し後に暗黙の `wait` が入る。

  ```
  result = @socket.b_transport(cmd: :READ, addr: 0x100)
  puts result.status   # => :OK
  ```

## FIFO

* `new(size: 5, width: 8) -> FIFO`

  キャパシティ `size`、VCD 記録ビット長 `width` の FIFO を返す。

  ```
  fifo = FIFO.new(size: 5, width: 8)
  ```

* `reader -> FIFOReader`

  読み出し用インスタンスを返す。

  ```
  reader = fifo.reader
  ```

* `writer -> FIFOWriter`

  書き込み用インスタンスを返す。

  ```
  writer = fifo.writer
  ```

**FIFOWriter**

* `write(data)`

  FIFO にデータを書き込む。データは次のクロックで読み出し可能になる。

  ```
  writer.write(42)
  writer.write(MyPayload.new(cmd: :READ))
  ```

**FIFOReader**

* `read -> val`

  FIFO からデータを読み出す。データがなければ読み出し可能になるまでブロックする。

  ```
  val = reader.read
  ```

* `has_data? -> bool`

  読み出し可能なデータがあれば `true` を返す。

  ```
  if reader.has_data?
    val = reader.read
  end
  ```

## Event

* `new -> Event`

  Event を初期化して返す。

  ```
  event = Event.new
  ```

* `reader -> EventReader`

  受信用インスタンスを返す。

  ```
  reader = event.reader
  ```

* `writer -> EventWriter`

  送信用インスタンスを返す。

  ```
  writer = event.writer
  ```

**EventWriter**

* `notify`

  即時通知。同一 TLM サイクル内で待機中の Fiber を起床させる。

  ```
  writer.notify
  ```

* `notify_deferred`

  遅延通知。次のクロック通知フェーズで待機中の Fiber を起床させる。

  ```
  writer.notify_deferred
  ```

**EventReader**

* `wait`

  通知が来るまでブロックする。

  ```
  reader.wait
  ```

* `| other -> EventOrReader`

  OR 結合。どちらかのイベントが発火したときに起床する。

  ```
  (reader_a | reader_b).wait
  ```

* `& other -> EventAndReader`

  AND 結合。両方のイベントが発火したときに起床する。

  ```
  (reader_a & reader_b).wait
  ```

## Payload

* `field(name, width:, enum: nil)` （クラスメソッド）

  フィールドを定義する。`width:` はビット幅、`enum:` は Symbol → 整数のマッピング。

  ```
  class MyPayload < DeepSveite::Payload
    field :cmd,    width: 2, enum: { READ: 0, WRITE: 1 }
    field :addr,   width: 16
    field :status, width: 1, enum: { OK: 0, ERROR: 1 }
  end
  ```

* `new(**kwargs) -> Payload`

  フィールド値をキーワード引数で指定して Payload を生成する。省略したフィールドは `nil`。

  ```
  p = MyPayload.new(cmd: :READ, addr: 0x100)
  ```

* `<field_name> -> val`

  フィールド値を返す。enum フィールドは Symbol で返る。

  ```
  p.cmd    # => :READ
  p.addr   # => 256
  ```

* `<field_name> = val`

  フィールドに値を設定する。enum フィールドは Symbol で設定する。

  ```
  p.status = :OK
  p.addr   = 0x200
  ```

## Module

* `always_comb(method_name, reads: nil)`

  組み合わせ回路のメソッドを登録する。`reads:` で監視する入力信号名を指定する。
  省略すると、Module のインスタンス変数のうち読み出し可能な Wire / Reg / WireArray / RegArray
  （Module 内で定義した信号と `.in` ポート。`.out` ポートは含まない）を自動収集する。
  WireArray / RegArray は、いずれかの要素が変化したときに再評価される。

  ```
  class MyModule < DeepSveite::Module
    always_comb :calc            # .in 接続の Wire と Reg を自動収集
  end

  class MyModule < DeepSveite::Module
    always_comb :calc, reads: [:a, :b]   # 監視信号を明示する場合
  end
  ```

* `always_ff(method_name, cond:)`

  順序回路のメソッドを登録する。`cond:` でクロックエッジを指定する。

  ```
  class MyModule < DeepSveite::Module
    always_ff :tick, cond: [:clk.posedge]
  end
  ```

* `process(method_name)`

  TLM プロセスのメソッドを登録する。`sim.build` 後に Fiber として起動される。

  ```
  class MyModule < DeepSveite::Module
    process :run
  end
  ```

* `vcd_signal(name, width:, size: nil)`

  インスタンス変数を VCD プローブとして登録する。
  `size:` を指定すると配列として登録する（配列の場合は省略不可）。
  指定なしの場合、Integer はスカラー、Hash はキー出現時に動的登録される。

  ```
  class MyModule < DeepSveite::Module
    vcd_signal :count,  width: 8
    vcd_signal :regs,   width: 8, size: 16
    vcd_signal :cache,  width: 16
  end
  ```

* `wait`

  次のクロックサイクルまで処理を中断する。`process` 内で使用する。

  ```
  def run
    loop do
      @count += 1
      wait
    end
  end
  ```

## always_comb

Module 内で `always_comb` を宣言し、組み合わせ回路のメソッドを定義する。
入力信号が変化するたびに自動で呼び出される。出力は Wire に書き込む。

```
class Adder < DeepSveite::Module
  always_comb :calc

  def calc
    @result.w = @a.w + @b.w
  end
end
```

## always_ff

Module 内で `always_ff` を宣言し、順序回路のメソッドを定義する。
指定したクロックエッジで呼び出される。出力は Reg にノンブロッキング代入する。

```
class Counter < DeepSveite::Module
  always_ff :tick, cond: [:clk.posedge]

  def tick
    @count.r = @count.r + 1
  end
end
```

## TestBench

* `new -> TestBench`

  TestBench を初期化する。TestBench 直下に宣言した Wire に `sim.step` の前に設定した値は、
  そのステップのクロック変化と同時に反映される。

  ```
  class Bench < DeepSveite::TestBench
    attr_reader :clk, :dut

    def initialize
      @clk = Wire.new
      @dut = MyModule.new
      @dut.clk = @clk.in
      super()
    end
  end
  ```

## Simulator

* `new(test_bench, clock = nil) -> Simulator`

  シミュレータを初期化する。`clock` を省略すると内部クロックを使用する。

  ```
  sim = Simulator.new(tb, tb.clk)
  ```

* `build`

  モジュール階層を走査し、信号・プロセスをシミュレータに登録する。
  `VCD.new` の前に呼び出す。

  ```
  sim.build
  ```

* `step`

  クロックを半周期進める。RTL サイクル・TLM サイクルを順に実行する。

  ```
  sim.step
  ```

* `run { halt_condition }`

  `halt_condition` が `true` を返すまで `step` を繰り返す。RTL/TLM 混在時に使用する。

  ```
  n = 0
  sim.run { (n += 1) >= 10 }
  ```

* `run`

  ブロックなしで呼び出す場合は TLM のみの構成に使用する。
  全 TLM プロセスの Fiber が終了したら停止する。

  ```
  sim.run
  ```

## VCD

* `new(sim, filename: "dump.vcd", timescale: "1 ns", time_step: 10) -> VCD`

  `sim.build` の後に生成する。生成時点の初期値を time=0 として記録する。
  生成後は `sim.step` / `sim.run` ごとに変化を自動収集する。

  ```
  sim.build
  vcd = VCD.new(sim, filename: "out.vcd")
  ```

* `write(filename = @filename)`

  収集した変化を VCD ファイルに書き出す。

  ```
  vcd.write
  vcd.write("other.vcd")   # ファイル名を上書きして出力することもできる
  ```

## シミュレーションのスケジューリング

RTL は SystemVerilog と同様に、評価イベントと更新イベントで動作する。
評価イベントは `always_comb` / `always_ff` の実行、更新イベントは信号の値の反映を指す。

* **Active 領域** — 評価イベントを実行する。
  `Wire` への書き込みは更新イベントとして Active に登録され、値が変化するとその Wire を参照する評価イベントが Active に登録される。
* **NBA 領域** — Active が空になったあとに、`Reg` への書き込み（ノンブロッキング代入）を反映する。
  値が変化した Reg を参照する評価イベントは Active に登録される。
* Active と NBA が両方空になるまで繰り返し、同一の `sim.step` 内で収束する。
  `always_ff` が出力した Reg を参照する `always_comb` も、同じ `sim.step` 内で評価される。

`always_ff` がクロックエッジで読む Wire / Reg の値は、そのエッジ直前に確定している値である。
2 段のシフトレジスタでは、後段は前段の更新前の値を取り込む。

TestBench で `sim.step` の前に設定した入力は、そのステップのクロック変化と同時に反映される。
そのエッジで起動する `always_ff` からは設定後の値が見える。

`Wire` の書き込みは更新イベント経由のため、同じプロセス内で書いた直後に読むと、書く前の値が返る。

```ruby
def calc
  @y.w = 1
  a = @y.w    # a は 1 ではなく、書く前の値
end
```

| 信号                      | RTL プロセス内の書き込み | プロセス外（TLM / TestBench / initialize）の書き込み |
|---------------------------|--------------------------|------------------------------------------------------|
| `Wire`                    | 更新イベント（Active）   | 次の `sim.step` の先頭で反映                         |
| `Reg`                     | NBA                      | 次の `sim.step` の NBA 領域で反映                    |
| `WireArray` / `RegArray`  | 更新イベント / NBA       | 即時反映                                             |

書き込んだ値は信号の `width` でマスクされる（幅を超えた上位ビットは捨てられる）。
負数は 2 の補数になり（`-1` は 8bit で `0xFF`）、`true` / `false` は `1` / `0` になる。
たとえば 8bit の Wire / Reg に `255 + 1` を書くと `0` になる。

同じ信号を異なる `always_comb` / `always_ff` が駆動すると、エラー（多重ドライバ）になる。
同一プロセス内で複数回書いた場合は、最後の値が有効になる。
RTL プロセス外（TLM / TestBench）からの書き込みは多重ドライバの検査対象外で、最後に書いた値が有効になる。
