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

  def self.verbose=(val)
    @verbose = val
  end

  def self.verbose?
    !!@verbose
  end

  def self.error_strings
    @error_strings ||= ['ERROR']
  end

  def self.error_strings=(val)
    unless val.is_a?(Array)
      fail 'OrigenSim.error_strings can only be set to an array of string values!'
    end
    @error_strings = val
  end

  def self.log_strings
    @log_strings ||= []
  end

  def self.log_strings=(val)
    unless val.is_a?(Array)
      fail 'OrigenSim.log_strings can only be set to an array of string values!'
    end
    @log_strings = val
  end
end
OrigenSim.__instantiate_simulator__
