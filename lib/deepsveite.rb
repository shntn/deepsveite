# frozen_string_literal: true

require 'set'

class Symbol
  def posedge = DeepSveite::ConditionDescriptor.new(self, :posedge)
  def negedge  = DeepSveite::ConditionDescriptor.new(self, :negedge)
end

require_relative "deepsveite/vcdprobe"
require_relative "deepsveite/signal"
require_relative "deepsveite/conditiondescriptor"
require_relative "deepsveite/edgetrigger"
require_relative "deepsveite/module"
require_relative "deepsveite/wire"
require_relative "deepsveite/reg"
require_relative "deepsveite/wirearray"
require_relative "deepsveite/regarray"
require_relative "deepsveite/socket"
require_relative "deepsveite/fifo"
require_relative "deepsveite/event"
require_relative "deepsveite/environmentbuilder"
require_relative "deepsveite/simulator"
require_relative "deepsveite/testbench"
require_relative "deepsveite/vcd"


module DeepSveite
  @current_process = nil
  @_process_written_signals = {}
  class << self
    attr_accessor :current_process, :_process_written_signals
  end
end