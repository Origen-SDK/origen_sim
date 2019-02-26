require 'origen'
require_relative '../config/application.rb'
require 'origen_testers'
require 'origen_sim/origen_testers/api'
require 'origen_sim/origen/pins/pin'
require 'origen_sim/origen/top_level'
require 'origen_sim/origen/application/runner'
require 'origen_sim/origen/registers/reg'
module OrigenSim
  NUMBER_OF_COMMENT_LINES = 10

  # THIS FILE SHOULD ONLY BE USED TO LOAD RUNTIME DEPENDENCIES
  # If this plugin has any development dependencies (e.g. dummy DUT or other models that are only used
  # for testing), then these should be loaded from config/boot.rb

  # Example of how to explicitly require a file
  # require "origen_sim/my_file"

  autoload :Simulator, 'origen_sim/simulator'
  autoload :Tester, 'origen_sim/tester'
  autoload :Generator, 'origen_sim/generator'

  # Include a mapping for various sematics.
  INIT_PIN_STATE_MAPPING = {
    # Drive Low Options
    'drive_lo'       => 0,
    'drive-lo'       => 0,
    'drive_low'      => 0,
    'drive-low'      => 0,
    'lo'             => 0,
    'low'            => 0,
    '0'              => 0,

    # Drive High Options
    'drive_hi'       => 1,
    'drive-hi'       => 1,
    'drive_high'     => 1,
    'drive-high'     => 1,
    'hi'             => 1,
    'high'           => 1,
    '1'              => 1,

    # High Impedance Options
    'z'              => 2,
    'high_z'         => 2,
    'high-z'         => 2,
    'hi_z'           => 2,
    'hi-z'           => 2,
    'high_impedance' => 2,
    'high-impedance' => 2,
    '2'              => 2,

    # Disable Options
    '-1'             => -1,
    'disable'        => -1,
    'disabled'       => -1,
    'no_action'      => -1,
    'no-action'      => -1
  }

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

  def self.synopsys(options = {}, &block)
    Tester.new(options.merge(vendor: :synopsys), &block)
  end

  def self.icarus(options = {}, &block)
    Tester.new(options.merge(vendor: :icarus), &block)
  end

  def self.verbose=(val)
    @verbose = val
  end

  def self.verbose?
    !!(@verbose || Origen.debugger_enabled? || Origen.running_remotely?)
  end

  def self.flow=(val)
    @flow = val
  end

  def self.flow
    @flow
  end

  def self.socket_dir=(val)
    @socket_dir = val
  end

  def self.socket_dir
    @socket_dir
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

  def self.warning_strings
    @warning_strings ||= ['WARNING']
  end

  def self.warning_strings=(val)
    unless val.is_a?(Array)
      fail 'OrigenSim.warning_strings can only be set to an array of string values!'
    end
    @warning_strings = val
  end

  def self.warning_string_exceptions
    @warning_string_exceptions ||= []
  end

  def self.warning_string_exceptions=(val)
    unless val.is_a?(Array)
      fail 'OrigenSim.warning_string_exceptions can only be set to an array of string values!'
    end
    @warning_string_exceptions = val
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

  def self.error(message)
    simulator.error(message)
  end

  def self.run(name, options = {}, &block)
    # Load up the application and target
    Origen.load_application
    Origen.app.load_target!

    # Start up the simulator and run whatever's in the target block.
    # After the block completes, shutdown the simulator
    tester.simulator.setup_simulation(name)
    yield
    tester.simulator.complete_simulation(name)
  end

  def self.run_source(source, options = {})
    OrigenSim.run(source) do
      OrigenTesters::Decompiler.decompile(source).execute
    end
  end
end
OrigenSim.__instantiate_simulator__
