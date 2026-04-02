require_relative "../lib/deepsveite"

DS = DeepSveite

class Memory < DeepSveite::Module
  attr_accessor :mem_socket

  def initialize
    @mem_socket = DeepSveite::Socket.new(method: :b_transport)
    @mem = {}
    super()
  end

  def b_transport(payload)
    case payload[:cmd]
    when "READ"
      payload[:data] = @mem.fetch(payload[:addr], 0xFF)
      payload[:status] = "OK"
    when "WRITE"
      @mem[payload[:addr]] = payload[:data]
      payload[:status] = "OK"
    else
      payload[:status] = "ERROR"
    end
    payload
  end
end

class CPU < DeepSveite::Module
  process :run

  attr_accessor :mem_socket
  def initialize
    @mem_socket = DeepSveite::Socket.new
    super()
  end

  def run
    @mem_socket.b_transport(cmd: "WRITE", addr: 0x100, data: 0xAB)
    @mem_socket.b_transport(cmd: "WRITE", addr: 0x101, data: 0xCD)
    r0 = @mem_socket.b_transport(cmd: "READ", addr: 0x100)
    r1 = @mem_socket.b_transport(cmd: "READ", addr: 0x101)
    r2 = @mem_socket.b_transport(cmd: "READ", addr: 0xFFF)    # 未書き込みk
    puts "0x100=#{format('%02X', r0[:data])}, " \
         "0x101=#{format('%02X', r1[:data])}, " \
         "0xFFF=#{format('%02X', r2[:data])}(未初期化)"
  end
end

class Bench < DS::TestBench
  def initialize
    super()
    @mod_mem = Memory.new
    @mod_cpu = CPU.new
    @mod_cpu.mem_socket.bind(@mod_mem.mem_socket)
  end
end

def main
  tb = Bench.new
  sim = DeepSveite::Simulator.new(tb)
  sim.build
  sim.run
end

main