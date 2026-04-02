# frozen_string_literal: true

class Symbol
  def posedge = DeepSveite::ConditionDescriptor.new(self, :posedge)
  def negedge  = DeepSveite::ConditionDescriptor.new(self, :negedge)
end

require_relative "deepsveite/signal"
require_relative "deepsveite/conditiondescriptor"
require_relative "deepsveite/edgetrigger"
require_relative "deepsveite/module"
require_relative "deepsveite/wire"
require_relative "deepsveite/reg"
require_relative "deepsveite/socket"
require_relative "deepsveite/environmentbuilder"
require_relative "deepsveite/simulator"
require_relative "deepsveite/testbench"


module DeepSveite; end