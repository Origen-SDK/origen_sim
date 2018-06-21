# coding: utf-8
config = File.expand_path('../config', __FILE__)
require "#{config}/version"

Gem::Specification.new do |spec|
  spec.name          = "origen_sim"
  spec.version       = OrigenSim::VERSION
  spec.authors       = ["Stephen McGinty"]
  spec.email         = ["stephen.f.mcginty@gmail.com"]
  spec.summary       = "Plugin that provides a testbench environment to simulate Origen test patterns"
  #spec.homepage      = "http://origen-sdk.org/origen_sim"

  spec.required_ruby_version     = '>= 2'
  spec.required_rubygems_version = '>= 1.8.11'

  # Only the files that are hit by these wildcards will be included in the
  # packaged gem, the default should hit everything in most cases but this will
  # need to be added to if you have any custom directories
  spec.files         = Dir["lib/**/*.rb", "templates/**/*", "config/**/*.rb",
                           "bin/*", "lib/tasks/**/*.rake", "pattern/**/*.rb",
                           "program/**/*.rb", "ext/**/*"
                          ]
  spec.executables   = []
  spec.require_paths = ["lib"]

  # Add any gems that your plugin needs to run within a host application
  spec.add_runtime_dependency "origen", ">= 0.33.3"
  spec.add_runtime_dependency "origen_testers"
  spec.add_runtime_dependency "origen_verilog", ">= 0.5"
end
