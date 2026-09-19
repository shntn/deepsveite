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

## API

### Wire

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

### Reg

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

### WireArray

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

### RegArray

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

### Socket

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

### FIFO

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

### Event

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

### Payload

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

### Module

* `always_comb(method_name, reads: nil)`

  組み合わせ回路のメソッドを登録する。`reads:` で監視する入力信号名を指定する。
  省略すると `.in` で接続された Wire（入力ポート）と Reg を自動収集する。
  `.in` 接続していない Wire を読む場合は `reads:` で明示する必要がある。

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

### always_comb

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

### always_ff

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

### TestBench

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

### Simulator

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

### VCD

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


## Example


### TestBench, Simulator, VCD

**step を使った RTL シミュレーション（半周期ずつ手動制御）**

```ruby
class Counter < DeepSveite::Module
  attr_accessor :clk, :count
  always_ff :tick, cond: [:clk.posedge]

  def initialize
    @clk   = DeepSveite::Wire.new
    @count = DeepSveite::Reg.new(width: 8)
    super()
  end

  def tick
    @count.r = @count.r + 1
  end
end

class Bench < DeepSveite::TestBench
  attr_reader :clk, :dut

  def initialize
    @clk = DeepSveite::Wire.new
    @dut = Counter.new
    @dut.clk = @clk.in
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb, tb.clk)
sim.build

20.times { sim.step }
puts tb.dut.count.r   # => 10（posedge が 10 回発生）
```

**run { 条件 } を使った RTL シミュレーション（halt_condition が true になるまで step を繰り返す）**

```ruby
class Counter < DeepSveite::Module
  attr_accessor :clk, :count
  always_ff :tick, cond: [:clk.posedge]

  def initialize
    @clk   = DeepSveite::Wire.new
    @count = DeepSveite::Reg.new(width: 8)
    super()
  end

  def tick
    @count.r = @count.r + 1
  end
end

class Bench < DeepSveite::TestBench
  attr_reader :clk, :dut

  def initialize
    @clk = DeepSveite::Wire.new
    @dut = Counter.new
    @dut.clk = @clk.in
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb, tb.clk)
sim.build

n = 0
sim.run { (n += 1) >= 20 }
puts tb.dut.count.r   # => 10
```

**run（ブロックなし）を使った TLM のみのシミュレーション（全 process の Fiber 終了で自動停止）**

```ruby
class Worker < DeepSveite::Module
  process :run

  def run
    5.times do |i|
      puts i
      wait
    end
  end
end

class Bench < DeepSveite::TestBench
  def initialize
    @worker = Worker.new
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb)
sim.build
sim.run
```

**VCD を使う場合（sim.build の後に生成し、run / step の後に write する）**

```ruby
class Counter < DeepSveite::Module
  attr_accessor :clk, :count
  always_ff :tick, cond: [:clk.posedge]

  def initialize
    @clk   = DeepSveite::Wire.new
    @count = DeepSveite::Reg.new(width: 8)
    super()
  end

  def tick
    @count.r = @count.r + 1
  end
end

class Bench < DeepSveite::TestBench
  attr_reader :clk, :dut

  def initialize
    @clk = DeepSveite::Wire.new
    @dut = Counter.new
    @dut.clk = @clk.in
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb, tb.clk)
sim.build

vcd = DeepSveite::VCD.new(sim, filename: "out.vcd")
n = 0
sim.run { (n += 1) >= 20 }
vcd.write
```


### Wire / Reg

**always_comb — attr_accessor で信号を公開し TestBench から接続するパターン**

```ruby
class Adder < DeepSveite::Module
  attr_accessor :a, :b, :result
  always_comb :calc

  def initialize
    @a      = DeepSveite::Wire.new(width: 8)
    @b      = DeepSveite::Wire.new(width: 8)
    @result = DeepSveite::Wire.new(width: 8)
    super()
  end

  def calc
    @result.w = @a.w + @b.w
  end
end

class Bench < DeepSveite::TestBench
  attr_reader :clk, :a, :b, :dut

  def initialize
    @clk = DeepSveite::Wire.new
    @a   = DeepSveite::Wire.new(width: 8)
    @b   = DeepSveite::Wire.new(width: 8)
    @dut = Adder.new
    @dut.a = @a.in
    @dut.b = @b.in
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb, tb.clk)
sim.build

tb.a.w = 3
tb.b.w = 5
sim.step
puts tb.dut.result.w   # => 8
```

**always_comb — コンストラクタ引数で信号を受け取り initialize 内で接続するパターン**

```ruby
class Adder < DeepSveite::Module
  always_comb :calc

  def initialize(a, b, result)
    @a      = a.in
    @b      = b.in
    @result = result.out
    super()
  end

  def calc
    @result.w = @a.w + @b.w
  end
end

class Bench < DeepSveite::TestBench
  attr_reader :clk, :a, :b, :result

  def initialize
    @clk    = DeepSveite::Wire.new
    @a      = DeepSveite::Wire.new(width: 8)
    @b      = DeepSveite::Wire.new(width: 8)
    @result = DeepSveite::Wire.new(width: 8)
    @adder  = Adder.new(@a, @b, @result)
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb, tb.clk)
sim.build

tb.a.w = 10
tb.b.w = 20
sim.step
puts tb.result.w   # => 30
```

**always_ff — Reg のノンブロッキング代入**

```ruby
class Counter < DeepSveite::Module
  attr_accessor :clk, :count
  always_ff :tick, cond: [:clk.posedge]

  def initialize
    @clk   = DeepSveite::Wire.new
    @count = DeepSveite::Reg.new(width: 8)
    super()
  end

  def tick
    @count.r = @count.r + 1
  end
end

class Bench < DeepSveite::TestBench
  attr_reader :clk, :dut

  def initialize
    @clk = DeepSveite::Wire.new
    @dut = Counter.new
    @dut.clk = @clk.in
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb, tb.clk)
sim.build

20.times { sim.step }
puts tb.dut.count.r   # => 10
```


### WireArray / RegArray

**WireArray — 組み合わせ信号の定数テーブル（ルックアップテーブル）**

```ruby
class PaletteLUT < DeepSveite::Module
  attr_accessor :sel, :r_out, :g_out, :b_out
  always_comb :lookup

  PALETTE = [[0xFF, 0x00, 0x00], [0x00, 0xFF, 0x00], [0x00, 0x00, 0xFF]]

  def initialize
    @r_lut = DeepSveite::WireArray.new(width: 8, size: PALETTE.size)
    @g_lut = DeepSveite::WireArray.new(width: 8, size: PALETTE.size)
    @b_lut = DeepSveite::WireArray.new(width: 8, size: PALETTE.size)
    @sel   = DeepSveite::Wire.new(width: 4)
    @r_out = DeepSveite::Wire.new(width: 8)
    @g_out = DeepSveite::Wire.new(width: 8)
    @b_out = DeepSveite::Wire.new(width: 8)
    PALETTE.each_with_index { |(r, g, b), i| @r_lut[i] = r; @g_lut[i] = g; @b_lut[i] = b }
    super()
  end

  def lookup
    @r_out.w = @r_lut[@sel.w]
    @g_out.w = @g_lut[@sel.w]
    @b_out.w = @b_lut[@sel.w]
  end
end

class Bench < DeepSveite::TestBench
  attr_reader :clk, :sel, :lut

  def initialize
    @clk = DeepSveite::Wire.new
    @sel = DeepSveite::Wire.new(width: 4)
    @lut = PaletteLUT.new
    @lut.sel = @sel.in
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb, tb.clk)
sim.build

tb.sel.w = 1
sim.step
puts tb.lut.g_out.w   # => 255
```

**RegArray — 順序回路の RAM**

```ruby
class SyncRAM < DeepSveite::Module
  attr_accessor :clk, :we, :waddr, :din, :raddr, :dout
  always_ff :tick, cond: [:clk.posedge]

  def initialize(size: 8, width: 8)
    @mem   = DeepSveite::RegArray.new(width: width, size: size)
    @clk   = DeepSveite::Wire.new
    @we    = DeepSveite::Wire.new
    @waddr = DeepSveite::Wire.new(width: 4)
    @din   = DeepSveite::Wire.new(width: width)
    @raddr = DeepSveite::Wire.new(width: 4)
    @dout  = DeepSveite::Reg.new(width: width)
    super()
  end

  def tick
    @mem[@waddr.w] = @din.w if @we.w == 1
    @dout.r = @mem[@raddr.w]
  end
end

class Bench < DeepSveite::TestBench
  attr_reader :clk, :we, :waddr, :din, :raddr, :ram

  def initialize
    @clk   = DeepSveite::Wire.new
    @we    = DeepSveite::Wire.new
    @waddr = DeepSveite::Wire.new(width: 4)
    @din   = DeepSveite::Wire.new(width: 8)
    @raddr = DeepSveite::Wire.new(width: 4)
    @ram   = SyncRAM.new
    @ram.clk   = @clk.in
    @ram.we    = @we.in
    @ram.waddr = @waddr.in
    @ram.din   = @din.in
    @ram.raddr = @raddr.in
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb, tb.clk)
sim.build

tb.we.w = 1; tb.waddr.w = 0; tb.din.w = 0xAB
n = 0; sim.run { (n += 1) >= 2 }

tb.we.w = 0; tb.raddr.w = 0
n = 0; sim.run { (n += 1) >= 2 }
puts tb.ram.dout.r   # => 171
```


### Socket

```ruby
class MemPayload < DeepSveite::Payload
  field :cmd,    width: 1, enum: { READ: 0, WRITE: 1 }
  field :addr,   width: 16
  field :data,   width: 8
  field :status, width: 1, enum: { OK: 0, ERROR: 1 }
end

class Memory < DeepSveite::Module
  attr_accessor :socket

  def initialize
    @socket = DeepSveite::Socket.new(method: :b_transport, payload: MemPayload)
    @mem = {}
    super()
  end

  def b_transport(payload)
    case payload.cmd
    when :READ  then payload.data = @mem.fetch(payload.addr, 0)
    when :WRITE then @mem[payload.addr] = payload.data
    end
    payload.status = :OK
  end
end

class CPU < DeepSveite::Module
  attr_accessor :socket
  process :run

  def initialize
    @socket = DeepSveite::Socket.new
    super()
  end

  def run
    @socket.b_transport(cmd: :WRITE, addr: 0x100, data: 0xAB)
    result = @socket.b_transport(cmd: :READ, addr: 0x100)
    puts result.data     # => 171
    puts result.status   # => :OK
  end
end

class Bench < DeepSveite::TestBench
  def initialize
    @cpu = CPU.new
    @mem = Memory.new
    @cpu.socket.bind(@mem.socket)
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb)
sim.build
sim.run
```


### FIFO

**blocking read — データがなければ自動的に次のクロックまで待機する**

```ruby
class Sender < DeepSveite::Module
  attr_accessor :fifo_writer
  process :run

  def run
    5.times { |i| @fifo_writer.write(i * 10) }
  end
end

class Receiver < DeepSveite::Module
  attr_accessor :fifo_reader
  process :run

  def run
    5.times do
      val = @fifo_reader.read
      puts val
    end
  end
end

class Bench < DeepSveite::TestBench
  def initialize
    @fifo     = DeepSveite::FIFO.new(size: 8, width: 8)
    @sender   = Sender.new
    @receiver = Receiver.new
    @sender.fifo_writer   = @fifo.writer
    @receiver.fifo_reader = @fifo.reader
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb)
sim.build
sim.run
```

**has_data? — データの有無を確認してから読み出す**

```ruby
class Sender < DeepSveite::Module
  attr_accessor :fifo_writer
  process :run

  def run
    5.times { |i| @fifo_writer.write(i * 10) }
  end
end

class Receiver < DeepSveite::Module
  attr_accessor :fifo_reader
  process :run

  def run
    5.times do
      wait
      if @fifo_reader.has_data?
        val = @fifo_reader.read
        puts val
      end
    end
  end
end

class Bench < DeepSveite::TestBench
  def initialize
    @fifo     = DeepSveite::FIFO.new(size: 8, width: 8)
    @sender   = Sender.new
    @receiver = Receiver.new
    @sender.fifo_writer   = @fifo.writer
    @receiver.fifo_reader = @fifo.reader
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb)
sim.build
sim.run
```


### Event

**notify / wait — 即時通知**

```ruby
class Notifier < DeepSveite::Module
  attr_accessor :event_writer
  process :run

  def run
    3.times do
      wait
      @event_writer.notify
    end
  end
end

class Waiter < DeepSveite::Module
  attr_accessor :event_reader
  process :run

  def run
    3.times do
      @event_reader.wait
      puts "event received"
    end
  end
end

class Bench < DeepSveite::TestBench
  def initialize
    event = DeepSveite::Event.new
    @notifier = Notifier.new
    @waiter   = Waiter.new
    @notifier.event_writer = event.writer
    @waiter.event_reader   = event.reader
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb)
sim.build
sim.run
```

**notify_deferred — 遅延通知（次のクロック通知フェーズで起床）**

```ruby
class Notifier < DeepSveite::Module
  attr_accessor :event_writer
  process :run

  def run
    3.times do
      wait
      @event_writer.notify_deferred
    end
  end
end

class Waiter < DeepSveite::Module
  attr_accessor :event_reader
  process :run

  def run
    3.times do
      @event_reader.wait
      puts "event received"
    end
  end
end

class Bench < DeepSveite::TestBench
  def initialize
    event = DeepSveite::Event.new
    @notifier = Notifier.new
    @waiter   = Waiter.new
    @notifier.event_writer = event.writer
    @waiter.event_reader   = event.reader
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb)
sim.build
sim.run
```

**OR 結合 — どちらかのイベントが発火したときに起床する**

```ruby
class Notifier < DeepSveite::Module
  attr_accessor :event_writer
  process :run

  def run
    wait
    @event_writer.notify
  end
end

class Waiter < DeepSveite::Module
  attr_accessor :event_reader_a, :event_reader_b
  process :run

  def run
    (@event_reader_a | @event_reader_b).wait
    puts "event received"
  end
end

class Bench < DeepSveite::TestBench
  def initialize
    @event_a  = DeepSveite::Event.new
    @event_b  = DeepSveite::Event.new
    @notifier = Notifier.new
    @waiter   = Waiter.new
    @notifier.event_writer  = @event_a.writer
    @waiter.event_reader_a  = @event_a.reader
    @waiter.event_reader_b  = @event_b.reader
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb)
sim.build
sim.run
```

**AND 結合 — 両方のイベントが発火したときに起床する**

```ruby
class NotifierA < DeepSveite::Module
  attr_accessor :event_writer
  process :run

  def run
    wait
    @event_writer.notify
  end
end

class NotifierB < DeepSveite::Module
  attr_accessor :event_writer
  process :run

  def run
    2.times { wait }
    @event_writer.notify
  end
end

class Waiter < DeepSveite::Module
  attr_accessor :event_reader_a, :event_reader_b
  process :run

  def run
    (@event_reader_a & @event_reader_b).wait
    puts "both events received"
  end
end

class Bench < DeepSveite::TestBench
  def initialize
    @event_a    = DeepSveite::Event.new
    @event_b    = DeepSveite::Event.new
    @notifier_a = NotifierA.new
    @notifier_b = NotifierB.new
    @waiter     = Waiter.new
    @notifier_a.event_writer = @event_a.writer
    @notifier_b.event_writer = @event_b.writer
    @waiter.event_reader_a   = @event_a.reader
    @waiter.event_reader_b   = @event_b.reader
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb)
sim.build
sim.run
```


## RTL/TLM Co-simulation

RTL モジュールと TLM モジュールは **Wire** を橋渡しとして通信する。

- TLM の `process` から Wire に書き込むと、次の `sim.step` で RTL 側に伝搬する
- RTL の `always_ff` / `always_comb` が出力した Wire の値を、TLM の `process` から読み取れる
- 混在構成では `sim.run { halt_condition }` を使い、RTL と TLM を同一タイムステップで進める

```ruby
class RTLCounter < DeepSveite::Module
  attr_accessor :clk, :enable, :count
  always_ff :tick, cond: [:clk.posedge]

  def initialize
    @clk    = DeepSveite::Wire.new
    @enable = DeepSveite::Wire.new
    @count  = DeepSveite::Reg.new(width: 8)
    super()
  end

  def tick
    @count.r = @count.r + 1 if @enable.w == 1
  end
end

class TLMController < DeepSveite::Module
  attr_accessor :enable
  process :run

  def initialize
    @enable = DeepSveite::Wire.new
    super()
  end

  def run
    @enable.w = 1
    5.times { wait }
    @enable.w = 0
  end
end

class Bench < DeepSveite::TestBench
  attr_reader :clk, :counter

  def initialize
    @clk        = DeepSveite::Wire.new
    @enable_sig = DeepSveite::Wire.new
    @ctrl       = TLMController.new
    @counter    = RTLCounter.new
    @ctrl.enable    = @enable_sig.out
    @counter.clk    = @clk.in
    @counter.enable = @enable_sig.in
    super()
  end
end

tb  = Bench.new
sim = DeepSveite::Simulator.new(tb, tb.clk)
sim.build

n = 0
sim.run { (n += 1) >= 20 }
puts tb.counter.count.r   # => 5（enable が High だった posedge 回数）
```

## Conventions & Rules

### シミュレーションのスケジューリング

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

同じ信号を異なる `always_comb` / `always_ff` が駆動すると、エラー（多重ドライバ）になる。
同一プロセス内で複数回書いた場合は、最後の値が有効になる。
RTL プロセス外（TLM / TestBench）からの書き込みは多重ドライバの検査対象外で、最後に書いた値が有効になる。

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

