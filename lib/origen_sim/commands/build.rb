require 'optparse'
require 'origen_sim'

options = {}

# App options are options that the application can supply to extend this command
app_options = @application_options || []
opt_parser = OptionParser.new do |opts|
  opts.banner = <<-EOT
Compile an RTL design into an object that Origen can simulate.

All configuration apart from target selection should be done when instantiating the
OrigenSim::Tester in an environment file. This encourages the configuration to be
checked in, enabling repeatable builds in future.

Usage: origen origen_sim:build [options]
  EOT
  opts.on('-e', '--environment NAME', String, 'Override the default environment, NAME can be a full path or a fragment of an environment file name') { |e| options[:environment] = e }
  opts.on('-t', '--target NAME', String, 'Override the default target, NAME can be a full path or a fragment of a target file name') { |t| options[:target] = t }
  opts.on('-pl', '--plugin PLUGIN_NAME', String, 'Set current plugin') { |pl_n|  options[:current_plugin] = pl_n }
  opts.on('--testrun', 'Displays the commands that will be generated but does not execute them') { options[:testrun] = true }
  opts.on('-i', '--incremental', 'Preserve existing compiled files to do an incremental build instead of starting from scratch') { options[:incremental] = true }
  opts.on('-d', '--debugger', 'Enable the debugger') {  options[:debugger] = true }
  app_options.each do |app_option|
    opts.on(*app_option) {}
  end
  opts.separator ''
  opts.on('-h', '--help', 'Show this message') { puts opts; exit 0 }
end

opt_parser.parse! ARGV
Origen.app.plugins.temporary = options[:current_plugin] if options[:current_plugin]
Origen.environment.temporary = options[:environment] if options[:environment]
Origen.target.temporary = options[:target] if options[:target]
Origen.app.load_target!

unless tester.is_a?(OrigenSim::Tester)
  puts 'The target/environment does not instantiate an OrigenSim::Tester instance!'
  exit
end

simulator = OrigenSim.simulator
config = simulator.configuration
tmp_dir = simulator.tmp_dir

unless options[:testrun]
  FileUtils.rm_rf(tmp_dir) unless options[:incremental]
  FileUtils.mkdir_p(tmp_dir)
  FileUtils.rm_rf(simulator.compiled_dir) unless options[:incremental]
  FileUtils.mkdir_p(simulator.compiled_dir)
  FileUtils.rm_rf(simulator.artifacts_dir)
  FileUtils.mkdir_p(simulator.artifacts_dir)
  Array(config[:artifacts] || config[:artifact]).each do |f|
    FileUtils.cp(f, simulator.artifacts_dir)
  end

  # Create the testbench for the current Origen target and simulator vendor
  Origen.app.runner.launch action:            :compile,
                           files:             "#{Origen.root!}/templates/rtl_v/origen.v.erb",
                           output:            tmp_dir,
                           check_for_changes: false,
                           options:           { vendor: config[:vendor], top: config[:rtl_top] }
end

case config[:vendor]
when :icarus
  # Compile the VPI extension first
  Dir.chdir tmp_dir do
    system "iverilog-vpi #{Origen.root!}/ext/*.c -DICARUS --name=origen"
    system "mv origen.vpi #{simulator.compiled_dir}"
  end
  # Build the object containing the DUT and testbench
  cmd = "iverilog -o #{simulator.compiled_dir}/dut.vvp"
  Array(config[:rtl_dir] || config[:rtl_dirs]).each do |dir|
    cmd += " -I #{dir}"
  end
  Array(config[:rtl_file] || config[:rtl_files]).each do |f|
    cmd += " #{f}"
  end
  cmd += " #{tmp_dir}/origen.v"

when :cadence
  cmd = config[:irun] || 'irun'
  Array(config[:rtl_file] || config[:rtl_files]).each do |f|
    cmd += " #{f}"
  end
  Array(config[:lib_file] || config[:lib_files]).each do |f|
    cmd += " -v #{f}"
  end
  Array(config[:rtl_dir] || config[:rtl_dirs]).each do |dir|
    cmd += " -incdir #{dir}"
  end
  cmd += " #{tmp_dir}/origen.v -top origen -timescale 1ns/1ns"
  cmd += " -nclibdirpath #{simulator.compiled_dir}"
  cmd += " #{Origen.root!}/ext/*.c -ccargs \"-std=gnu99\""
  cmd += ' -elaborate -snapshot origen -access +rw'
  cmd += " #{config[:explicit].strip.gsub(/\s+/, ' ')}" if  config[:explicit]
end

puts cmd
unless options[:testrun]
  Dir.chdir tmp_dir do
    system cmd
  end
end
