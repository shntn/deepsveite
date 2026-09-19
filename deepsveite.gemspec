Gem::Specification.new do |s|
  s.name = "deepsveite"
  s.version = "0.2.0"
  s.summary = "TLM/RTL prototyping framework"
  s.description = "A lightweight RTL/TLM hardware simulation framework written in pure Ruby. " \
                  "Supports Wire/Reg, always_comb/always_ff, Socket/FIFO/Event, RTL/TLM co-simulation and VCD output."
  s.authors = ["shntn"]
  s.homepage = "https://github.com/shntn/deepsveite"
  s.license = "MIT"
  s.required_ruby_version = ">= 3.0"
  s.files = Dir["lib/**/*.rb", "docs/**/*.md", "examples/ex_*.rb", "README.md", "LICENSE"]
end
