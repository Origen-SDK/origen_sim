require 'origen'
require_relative '../config/application.rb'
require 'origen_testers'
require 'origen_sim/origen_testers/api'
require 'origen_sim/origen/pins/pin'
require 'origen_sim/origen/top_level'
module OrigenSim
  # THIS FILE SHOULD ONLY BE USED TO LOAD RUNTIME DEPENDENCIES
  # If this plugin has any development dependencies (e.g. dummy DUT or other models that are only used
  # for testing), then these should be loaded from config/boot.rb

  # Example of how to explicitly require a file
  # require "origen_sim/my_file"

  autoload :Simulator, 'origen_sim/simulator'
  autoload :Tester, 'origen_sim/tester'
  autoload :Generator, 'origen_sim/generator'

  def self.__instantiate_simulator__
    @simulator ||= Simulator.new
  end

  def self.simulator
    @simulator
  end

  # Provide some shortcut methods to set the vendor
  def self.generic(options = {}, &block)
    Tester.new(options.merge(vendor: :generic), &block)
  end

  def self.cadence(options = {}, &block)
    Tester.new(options.merge(vendor: :cadence), &block)
  end

  def self.synopsys(optoins = {}, &block)
    Tester.new(options.merge(vendor: :synopsys), &block)
  end

  def self.icarus(options = {}, &block)
    Tester.new(options.merge(vendor: :icarus), &block)
  end
end
OrigenSim.__instantiate_simulator__
