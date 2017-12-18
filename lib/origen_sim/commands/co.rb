require 'optparse'
require 'origen/commands/helpers'

options = {}

# App options are options that the application can supply to extend this command
app_options = @application_options || []
opt_parser = OptionParser.new do |opts|
  opts.banner = <<-EOT
Checkout the simulation object for the current or given environment/target.

Note that this will force a new checkout and will overwrite whatever is in your workspace.

Usage: origen sim:co [options]
  EOT
  opts.on('-e', '--environment NAME', String, 'Override the default environment, NAME can be a full path or a fragment of an environment file name') { |e| options[:environment] = e }
  opts.on('-t', '--target NAME', String, 'Override the default target, NAME can be a full path or a fragment of a target file name') { |t| options[:target] = t }
  opts.on('-d', '--debugger', 'Enable the debugger') {  options[:debugger] = true }
  # Apply any application option extensions to the OptionParser
  opts.separator ''
  opts.on('-h', '--help', 'Show this message') { puts opts; exit }
end

opt_parser.parse! ARGV

Origen.environment.temporary = options[:environment] if options[:environment]
Origen.target.temporary = options[:target] if options[:target]
Origen.load_target

unless tester.sim?
  Origen.log.error 'To run the sim:co command your target/environment must instantiate an OrigenSim::Tester'
  exit 1
end

options[:force] = true
tester.simulator.fetch_simulation_objects(options)
