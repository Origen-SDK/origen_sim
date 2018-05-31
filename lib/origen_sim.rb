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
  
  def self.verbose=(val)
    @verbose = val
  end

  def self.verbose?
    !!(@verbose || Origen.debugger_enabled?)
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

  def self.error_string_exceptions
    @error_string_exceptions ||= []
  end

  def self.error_string_exceptions=(val)
    unless val.is_a?(Array)
      fail 'OrigenSim.error_string_exceptions can only be set to an array of string values!'
    end
    @error_string_exceptions = val
  end

  def self.stderr_string_exceptions
    @stderr_string_exceptions ||= []
  end

  def self.stderr_string_exceptions=(val)
    unless val.is_a?(Array)
      fail 'OrigenSim.error_string_exceptions can only be set to an array of string values!'
    end
    @stderr_string_exceptions = val
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

  def self.fail_on_stderr=(val)
    @fail_on_stderr = val
  end

  def self.fail_on_stderr
    defined?(@fail_on_stderr) ? @fail_on_stderr : true
  end
end
OrigenSim.__instantiate_simulator__
