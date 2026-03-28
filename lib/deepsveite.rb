# frozen_string_literal: true

class Symbol
  def posedge = "#{self}.posedge"
  def negedge  = "#{self}.negedge"
end

require_relative "deepsveite/signal"
require_relative "deepsveite/module"
require_relative "deepsveite/wire"
require_relative "deepsveite/reg"
require_relative "deepsveite/environmentbuilder"
require_relative "deepsveite/simulator"
require_relative "deepsveite/testbench"


module DeepSveite; end