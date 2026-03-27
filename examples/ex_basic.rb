require_relative "../lib/deepsveite"

include DeepSveite

DS = DeepSveite

class MyModule < DS::Module
  always_comb :routine, reads: [:din1, :din2], writes: [:internal]
  always_comb :routine2, reads: [:internal], writes: [:dout]

  def initialize(din1, din2, dout)
    @din1 = din1.in
    @din2 = din2.in
    @dout = dout.out
    @internal = Wire.new(width: 8)
    super()
  end

  def routine
    @internal.w = @internal.w + @din1.w + @din2.w
    print "internal : #{@internal._content._pending}\n"
  end

  def routine2
    @dout.w = @internal.w
    print "dout : #{@dout._content._pending}\n"
  end
end

class Bench < DS::TestBench
  def initialize
    super()
    @din1 = DeepSveite::Wire.new(width: 8)
    @din2 = DeepSveite::Wire.new(width: 8)
    @din1.w = 1
    @dout = DeepSveite::Wire.new(width: 8)
    @mod = MyModule.new(@din1, @din2, @dout)
  end
end

def main
  tb = Bench.new
  sim = DS::Simulator.new(tb)
  sim.build
  sim.step
end

main