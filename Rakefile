# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs    << "test"
  t.pattern = "tests/*.rb"
  t.verbose = true
end

task default: :test
