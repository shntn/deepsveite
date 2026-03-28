require_relative "../lib/deepsveite"

class ProgramCounter < DeepSveite::Module
  def initialize(clk, n_clr, cp, ep, pc_out)
    @clk = clk.in
    @n_clr = n_clr.in
    @cp = cp.in
    @ep = ep.in
    @pc_out = pc_out.out
    @pc = DeepSveite::Reg.new(width: 4)
    @pc_next = DeepSveite::Wire.new(width: 4)
    super()
  end

  always_ff :sequential, cond: [:clk.posedge], reads: [:n_clk], writes: [:pc]
  def sequential_circuit
    if !@n_clr.w
      @pc.r = 0
    else
      @pc.r = @pc_next.w
    end
  end

  always_comb :combinational, reads: [:n_clk, :cp, :ep], writes: [:pc]
  def combinational_circuit
    @pc_next.w = @pc.r

    # リセット
    unless @n_clr.w
      @pc_next.w = 0
    end

    # PC 更新
    if @n_clr.w && @cp.w
      @pc_next.w = @pc.r + 1
    end

    # PC 出力
    if @ep.w
      @pc_out.w = @pc.r & 0x0F
    end
  end
end

class InputAndMemoryAddressRegister < DeepSveite::Module
  def initialize(clk, n_lm, ain, a)
    @clk = clk.in
    @n_lm = n_lm.in
    @ain = ain.in
    @a = a.out
    @a_reg = DeepSveite::Reg.new(width: 4)
    @a_reg_next = DeepSveite::Wire.new(width: 4)
    @select_a = DeepSveite::Wire.new(width: 4)
    super()
  end

  always_ff :sequential_circuit, cond: [:clk.posedge], reads: [:a_reg_next], writes: [:a_reg]
  def sequential_circuit
    @a_reg.r = @a_reg_next.w
  end

  always_comb :combinational_circuit,
              reads:[:a_reg, :n_lm, :ain, :select_a],
              writes: [:a_reg_next, :select_a, :a]
  def combinational_circuit
    @a_reg_next.w = @a_reg.r

    # アドレスを選択
    if @n_lm.w
      @select_a.w = @a_reg.r
    else
      @select_a.w = @ain.w & 0x0F
    end

    # 選択した A をラッチ
    @a_reg_next.w = @select_a.w

    # アドレス出力
    @a.w = @a_reg.r
  end
end

class Ram < DeepSveite::Module
  def initialize(clk, a, n_ce, d)
    @clk = clk.in
    @a = a.in
    @n_ce = n_ce.in
    @d = d.out
    @memory = [
              # addr  inst        Acc     B-Reg   Out-Reg
      0x09,   # 0x0   LDA  0x9    0x02    0x00    0x00
      0x1A,   # 0x1   ADD  0xA    0x05    0x03    0x00
      0x1B,   # 0x2   ADD  0xB    0x0A    0x05    0x00
      0x2C,   # 0x3   SUB  0xC    0x06    0x04    0x00
      0xE0,   # 0x4   OUT         0x06    0x04    0x06
      0xF0,   # 0x5   HALT
      0x00,   # 0x6
      0x00,   # 0x7
      0x00,   # 0x8
      0x02,   # 0x9
      0x03,   # 0xA
      0x05,   # 0xB
      0x04,   # 0xC
      0x00,   # 0xD
      0x00,   # 0xE
      0x00    # 0xF
    ]
    super()
  end

  always_comb :combinational_circuit, reads: [:n_ce, :a], writes: [:d]
  def combinational_circuit
    unless @n_ce.w
      @d.w = @memory[@a.w & 0x0F]
    end
  end
end


class InstructionRegister < DeepSveite::Module
  def initialize(clk, clr, d, n_li, n_ei, inst, imm)
    @clk = clk.in
    @clr = clr.in
    @d = d.in
    @n_li = n_li.in
    @n_ei = n_ei.in
    @inst = inst.out
    @imm = imm.out
    @inst_latch = DeepSveite::Reg.new(width: 4)
    @imm_latch = DeepSveite::Reg.new(width: 4)
    @data = DeepSveite::Wire.new(width: 8)
    @inst_next = DeepSveite::Wire.new(width: 4)
    @imm_next = DeepSveite::Wire.new(width: 4)
    super()
  end

  always_ff :sequential_circuit,
            cond: [:clk.posedge],
            reads: [:inst_next, :imm_next],
            writes: [:inst_latch, :imm_latch]
  def sequential_circuit
    if @clr.w
      @inst_latch.r = 0
    @imm_latch.r = 0
  else
    @inst_latch.r = @inst_next.w
    @imm_latch.r = @imm_next.w
    end
  end

  always_comb :combinational_circuit,
              reads: [:inst_latch, :imm_latch, :clr, :n_li, :n_ei, :d, :inst, :imm],
              writes: [:inst_next, :imm_next, :data, :inst, :imm]
  def combinational_circuit
    @inst_next.w = @inst_latch.r
    @imm_next.w = @imm_latch.r

    # リセット
    if @clr.w
      @inst_next.w = 0
      @imm_next.w = 0
    end

    # ラッチするデータを選択
    if @n_li.w
      @data = ((@inst_latch.r << 4) & 0xF0) | (@imm_latch.r & 0x0F)
    else
      @data.w = @d.w
    end

    # ラッチ
    unless @clr.w
      @inst_next.w = @data & 0xF0 >> 4
      @imm_next.w = @data & 0x0F
    end

    # ラッチしたデータを出力
    unless @n_ei.w
      @inst.w = @inst_latch.r
      @imm.w = (@imm.w & 0xF0) | @imm_latch.r
    end
  end
end

class ControllerSequencer < DeepSveite::Module
  def initialize(clk, n_clr, inst, cp, ep, n_lm, n_ce, n_li, n_ei, n_la, ea, su, eu, n_lb, n_lo, n_halt)
    @clk = clk.in
    @n_clr = n_clr.in
    @inst = inst.in
    @cp = cp.out
    @ep = ep.out
    @n_lm = n_lm.out
    @n_ce = n_ce.out
    @n_li = n_li.out
    @n_ei = n_ei.out
    @n_la = n_la.out
    @ea = ea.out
    @su = su.out
    @eu = eu.out
    @n_lb = n_lb.out
    @n_lo = n_lo.out
    @n_halt = n_halt.out
    @t = DeepSveite::Reg.new(width: 4)  # 0 = T1, ..., 5 = T6
    @t_next = DeepSveite::Wire.new(width: 4)
    @inst_lda = DeepSveite::Wire.new(width: 1)
    @inst_add = DeepSveite::Wire.new(width: 1)
    @inst_sub = DeepSveite::Wire.new(width: 1)
    @inst_out = DeepSveite::Wire.new(width: 1)
    super()
  end

  always_ff :sequential_circuit,
            cond: [:clk.posedge],
            reads: [:n_clr, :t_next],
            writes: [:t]
  def sequential_circuit
    if !@n_clr.w
      @t.r = 0
    else
      @t.r = @t_next.w
    end
  end

  always_comb :combinational_circuit,
              reads: [:t, :inst, :inst_lda, :inst_add, :inst_sub, :inst_out],
              writes: [:t_next, :t, :inst_lda, :inst_add, :inst_sub, :inst_out, :n_halt, :cp, :ep, :n_lm, :n_ce, :n_li, :n_ei, :n_la, :ea, :su, :eu, :n_lb, :n_lo]
  def combinational_circuit
    @t_next.w = @t.r

    # Tステートを更新
    if @n_clr.w
      if @t.r == 5
        @t_next.w = 0
      else
        @t_next.w = @t.r + 1
      end
    else
      @t_next.w = 0

      # inst から命令をデコード
      @inst_lda.w = @inst.w == 0x0
      @inst_add.w = @inst.w == 0x1
      @inst_sub.w = @inst.w == 0x2
      @inst_out.w = @inst.w == 0xE
      @n_halt.w = not (@inst.w == 0xF)

      # 制御信号
      @cp.w = @t.r== 1
      @ep.w = @t.r == 0
      @n_lm.w = !(    (@t.r == 0)
                   || (@t.r == 3 && @inst_lda.w)
                   || (@t.r == 3 && @inst_add.w)
                   || (@t.r == 3 && @inst_sub.w))
      @n_ce.w = !(    (@t.r == 2)
                   || (@t.r == 4 && @inst_lda.w)
                   || (@t.r == 4 && @inst_add.w)
                   || (@t.r == 4 && @inst_sub.w))
      @n_li.w = !(@t.r == 2)
      @n_ei.w = !(    (@t.r == 3 && @inst_lda.w)
                   || (@t.r == 3 && @inst_add.w)
                   || (@t.r == 3 && @inst_sub.w))
      @n_la.w = !(    (@t.r == 4 && @inst_lda.w)
                   || (@t.r == 5 && @inst_add.w)
                   || (@t.r == 5 && @inst_sub.w))
      @ea.w = (@t.r == 3) && @inst_out.w
      @su.w = (@t.r == 5) && @inst_sub.w
      @eu.w = (    (@t.r == 5 && @inst_add.w)
                || (@t.r == 5 && @inst_sub.w))
      @n_lb.w = !(    (@t.r == 4 && @inst_add.w)
                   || (@t.r == 4 && @inst_sub.w))
      @n_lo.w = !(@t.r == 3 && @inst_out.w)
    end
  end
end


class Accumulator < DeepSveite::Module
  def initialize(clk, din, n_la, ea, dout_to_bus, dout_to_alu)
    @clk = clk.in
    @din = din.in
    @n_la = n_la.in
    @ea = ea.in
    @dout_to_bus = dout_to_bus.out
    @dout_to_alu = dout_to_alu.out
    @data = DeepSveite::Reg.new(width: 8)
    @data_next = DeepSveite::Wire.new(width: 8)
    @data_in = DeepSveite::Wire.new(width: 8)
    super()
  end

  always_ff :sequential_circuit, cond: [:clk.posedge], reads: [:data_next], writes: [:data]
  def sequential_circuit
    @data.r = @data_next.w
  end

  always_comb :combinational_circuit,
              reads: [:data, :n_la, :ea, :din, :data_in],
              writes: [:data_next, :data_in, :data_next, :dout_to_alu, :dout_to_bus]
  def combinational_circuit
    @data_next.w = @data.r

    # 入力データ選択
    if @n_la.w
        @data_in.w = @data.r
    else
      @data_in.w = @din.w
    end

    # ラッチ
    @data_next.w = @data_in.w

    # 出力選択
    @dout_to_alu.w = @data.r
    if @ea.w
      @dout_to_bus.w = @data.r
    end
  end
end

class AdderSubtractor < DeepSveite::Module
  def initialize(clk, din1, din2, su, eu, data_out)
    @clk = clk.in
    @din1 = din1.in
    @din2 = din2.in
    @su = su.in
    @eu = eu.in
    @data_out = data_out.out
    @op2 = DeepSveite::Wire.new(width: 8)
    super()
  end

  always_comb :combinational_circuit,
              reads: [:su, :eu, :din2, :op2],
              writes: [:op2, :data_out]
  def combinational_circuit
    # Bレジスタから入力する値の選択
    if @su.w
      @op2.w = -@din2.w
    else
      @op2.w = @din2.w
    end

    # 出力選択
    if @eu.w
      @data_out.w = @din1.w + @op2.w
    end
  end
end

class BRegister < DeepSveite::Module
  def initialize(clk, din, n_lb, dout)
    @clk = clk.in
    @din = din.in
    @n_lb = n_lb.in
    @dout = dout.out
    @data = DeepSveite::Reg.new(width: 8)
    @data_next = DeepSveite::Wire.new(width: 8)
    @data_in = DeepSveite::Wire.new(width: 8)
    super()
  end

  always_ff :sequential_circuit, cond: [:clk.posedge], reads: [:data_next], writes: [:data]
  def sequential_circuit
    @data.r = @data_next.w
  end

  always_comb :combinational_circuit,
              reads: [:data, :n_lb, :din, :data_in],
              writes: [:data_next, :data_in, :data_next, :dout]
  def combinational_circuit
    @data_next.w = @data.r

    # 入力データ選択
    if @n_lb.w
      @data_in.w = @data.r
    else
      @data_in.w = @din.w
    end

    # ラッチ
    @data_next.w = @data_in.w

    # 出力選択
    @dout.w = @data.r
  end
end

class OutputRegister < DeepSveite::Module
  def initialize(clk, din, n_lo, dout)
    @clk = clk.in
    @din = din.in
    @n_lo = n_lo.in
    @dout = dout.out
    @data = DeepSveite::Reg.new(width: 8)
    @data_next = DeepSveite::Wire.new(width: 8)
    @data_in = DeepSveite::Wire.new(width: 8)
    super()
  end

  always_ff :sequential_circuit, cond: [:clk.posedge], reads: [:data_next], writes: [:data]
  def sequential_circuit
    @data.r = @data_next.w
  end

  always_comb :combinational_circuit,
              reads: [:data, :n_lo, :din, :data_in],
              writes: [:data_next, :data_in, :data_next, :dout]
  def combinational_circuit
    @data_next.w = @data.r

    # 入力データ選択
    if @n_lo.w
      @data_in.w = @data.r
    else
      @data_in.w = @din.w
    end

    # ラッチ
    @data_next.w = @data_in.w

    # 出力選択
    @dout.w = @data.r
  end
end

class BinaryDisplay < DeepSveite::Module
  attr_accessor :data

  def initialize(clk, din)
    @clk = clk.in
    @din = din.in
    @data = DeepSveite::Reg.new(width: 8)
    @data_next = DeepSveite::Wire.new(width: 8)
    super()
  end

  always_ff :sequential_circuit, cond: [:clk.posedge], reads: [:data_next], writes: [:data]
  def sequential_circuit
    @data.r = @data_next.w
  end

  always_comb :combinational_circuit, reads: [:din], writes: [:data_next]
  def combinational_circuit
    @data_next.w = @din.w
  end
end

class Sap1 < DeepSveite::Module
  attr_accessor :m_bd

  def initialize(clk, clr)
    @clk = clk.in
    @clr = clr.in

    # 生成信号
    @n_clr = DeepSveite::Wire.new
    @mar_out = DeepSveite::Wire.new(width: 4)
    @inst = DeepSveite::Wire.new(width: 4)
    @n_halt = DeepSveite::Wire.new(init: 1)
    @acc_out = DeepSveite::Wire.new(width: 8)
    @breg_out = DeepSveite::Wire.new(width: 8)
    @or_out = DeepSveite::Wire.new(width: 8)

    # bus
    @bus = DeepSveite::Wire.new(width: 8)

    # control signals
    @cp = DeepSveite::Wire.new
    @ep = DeepSveite::Wire.new
    @n_lm = DeepSveite::Wire.new(init: 1)
    @n_ce = DeepSveite::Wire.new(init: 1)
    @n_li = DeepSveite::Wire.new(init: 1)
    @n_ei = DeepSveite::Wire.new(init: 1)
    @n_la = DeepSveite::Wire.new
    @ea = DeepSveite::Wire.new
    @su = DeepSveite::Wire.new
    @eu = DeepSveite::Wire.new
    @n_lb = DeepSveite::Wire.new(init: 1)
    @n_lo = DeepSveite::Wire.new(init: 1)

    # モジュール
    @m_pc = ProgramCounter.new(@clk, @n_clr, @cp, @ep, @bus)

    @m_mar = InputAndMemoryAddressRegister.new(@clk, @n_lm, @bus, @mar_out)

    @m_ram = Ram.new(@clk, @mar_out, @n_ce, @bus)

    @m_ir = InstructionRegister.new(@clk, @clr, @bus, @n_li, @n_ei, @inst,@bus)

    @m_cs = ControllerSequencer.new(
                    @clk,
                    @n_clr, @inst,
                    @cp, @ep, @n_lm, @n_ce, @n_li,
                    @n_ei, @n_la, @ea, @su, @eu,
                    @n_lb, @n_lo, @n_halt)

    @m_acc = Accumulator.new(@clk, @bus, @n_la, @ea, @bus, @acc_out)

    @m_alu = AdderSubtractor.new(@clk, @acc_out, @breg_out, @su, @eu, @bus)

    @m_breg = BRegister.new(@clk, @bus, @n_lb, @breg_out)

    @m_or = OutputRegister.new(@clk, @bus, @n_lo, @or_out)

    @m_bd = BinaryDisplay.new(@clk, @or_out)

    super()
  end

  always_comb :combinational_circuit, reads: [:clr], writes: [:n_clr]
  def combinational_circuit
    @n_clr.w = not @clr.w
  end
end

class TbSAP1 < DeepSveite::TestBench
  attr_reader :clk, :clr, :sap1
  def initialize
    @clk = DeepSveite::Wire.new
    @clr = DeepSveite::Wire.new(init: 1)
    @sap1 = Sap1.new(@clk, @clr)
    super
  end

  def run(simulator)
    simulator.step
    simulator.step
    @clr.w = 0
    (6 * 6).times do
      simulator.step
    end
  end
end

def main
  tb = TbSAP1.new
  #vcd = VCDWriter()
  sim = DeepSveite::Simulator.new(tb, tb.clk)
  #vcd.open("sap1.vcd")
  tb.run(sim)
  print "Binary Display : #{tb.sap1.m_bd.data.r}\n"
  #vcd.close()
end

main
