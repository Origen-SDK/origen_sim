require 'optparse'
require 'origen_sim'
require_relative '../../../config/version'
require 'origen_verilog'

options = { source_dirs: [], testbench_name: 'origen', defines: [] }

# App options are options that the application can supply to extend this command
app_options = @application_options || []
opt_parser = OptionParser.new do |opts|
  opts.banner = <<-EOT
Build an Origen testbench and simulator VPI extension for the given top-level RTL design file (or a stub).

The created artifacts should be included in a compilation of the given design to create
an Origen-enabled simulation object that can be used to simulate Origen-based test patterns.

Usage: origen sim:build TOP_LEVEL_VERILOG_FILE [options]
  EOT
  opts.on('-o', '--output DIR', String, 'Override the default output directory') { |t| options[:output] = t }
  opts.on('-t', '--top NAME', String, 'Specify the top-level Verilog module name if OrigenSim can\'t work it out') { |t| options[:top_level_name] = t }
  opts.on('--testbench NAME', String, 'Specify the testbench name if different from \'origen\'') { |t| options[:testbench_name] = t }
  opts.on('-s', '--source_dir PATH', 'Directories to look for include files in (the directory containing the top-level is already considered)') do |path|
    options[:source_dirs] << path
  end
  opts.on('--define MACRO', 'Specify a compiler define') do |macro|
    options[:defines] << macro
  end
  opts.on('-d', '--debugger', 'Enable the debugger') {  options[:debugger] = true }
  app_options.each do |app_option|
    opts.on(*app_option) {}
  end
  opts.separator ''
  opts.on('-h', '--help', 'Show this message') { puts opts; exit 0 }
end

opt_parser.parse! ARGV

def _exit_fail_
  if $_testing_build_return_dut_
    return nil
  else
    exit 1
  end
end

unless ARGV.size > 0
  puts 'You must supply a path to the top-level RTL file'
  _exit_fail_
end
files = ARGV.join(' ')
rtl_top = files.split(/\s+/).last

ast = OrigenVerilog.parse_file(files, options)

unless ast
  puts 'Sorry, but the given top-level RTL file failed to parse'
  _exit_fail_
end

candidates = ast.top_level_modules
candidates = ast.modules if candidates.empty?

if candidates.size == 0
  puts "Sorry, couldn't find any Verilog module declarations in that file"
  _exit_fail_
elsif candidates.size > 1
  if options[:top_level_name]
    mod = candidates.find { |c| c.name == options[:top_level_name] }
  end
  unless mod
    puts "Sorry, couldn't work out what the top-level module is, please help by running again and specifying it via the --top switch with one of the following names:"
    candidates.each do |c|
      puts "  #{c.name}"
    end
    _exit_fail_
  end
else
  mod = candidates.first
end

rtl_top_module = mod.name

mod.to_top_level # Creates dut

if $_testing_build_return_dut_
  dut

else

  output_directory = options[:output] || Origen.config.output_directory

  Origen.app.runner.launch action:            :compile,
                           files:             "#{Origen.root!}/templates/rtl_v/origen.v.erb",
                           output:            output_directory,
                           check_for_changes: false,
                           quiet:             true,
                           options:           { vendor: :cadence, top: dut.name, incl: options[:incl_files] }

  Origen.app.runner.launch action:            :compile,
                           files:             "#{Origen.root!}/ext",
                           output:            output_directory,
                           check_for_changes: false,
                           quiet:             true,
                           options:           options

  dut.export(rtl_top_module, dir: "#{output_directory}", namespace: nil)

  puts
  puts
  puts '-----------------------------------------------------------'
  puts 'Cadence Incisive (irun)'
  puts '-----------------------------------------------------------'
  puts
  puts 'Add the following to your build script (AND REMOVE ANY OTHER TESTBENCH!):'
  puts
  puts "  #{output_directory}/origen.v \\"
  puts "  #{output_directory}/*.c \\"
  puts '  -ccargs "-std=c99" \\'
  puts '  -top origen \\'
  puts '  -elaborate  \\'
  puts '  -snapshot origen \\'
  puts '  -access +rw \\'
  puts '  -timescale 1ns/1ns'
  puts
  puts 'Here is an example which may work for the file you just parsed (add additional -incdir options at the end if required):'
  puts
  puts "  #{ENV['ORIGEN_SIM_IRUN'] || 'irun'} #{rtl_top} #{output_directory}/origen.v #{output_directory}/*.c -ccargs \"-std=c99\" -top origen -elaborate -snapshot origen -access +rw -timescale 1ns/1ns -incdir #{Pathname.new(rtl_top).dirname}"
  puts
  puts 'Copy the following directory (produced by irun) to simulation/<target>/cadence/. within your Origen application:'
  puts
  puts '  INCA_libs'
  puts
  puts '-----------------------------------------------------------'
  puts 'Synopsys VCS'
  puts '-----------------------------------------------------------'
  puts
  puts 'Add the following to your build script (AND REMOVE ANY OTHER TESTBENCH!):'
  puts
  puts "  #{output_directory}/origen.v \\"
  puts "  #{output_directory}/bridge.c \\"
  puts "  #{output_directory}/client.c \\"
  puts '  -CFLAGS "-std=c99" \\'
  puts '  +vpi \\'
  puts "  -use_vpiobj #{output_directory}/origen.c \\"
  puts '  +define+ORIGEN_VPD=1 \\'
  puts '  -debug_access+all \\'
  puts '  -PP \\'
  puts '  -timescale=1ns/1ns'
  puts
  puts 'Here is an example which may work for the file you just parsed (add additional -incdir options at the end if required):'
  puts
  puts "  #{ENV['ORIGEN_SIM_VCS'] || 'vcs'} #{rtl_top} #{output_directory}/origen.v #{output_directory}/bridge.c #{output_directory}/client.c -CFLAGS \"-std=c99\" +vpi -use_vpiobj #{output_directory}/origen.c -timescale=1ns/1ns  +define+ORIGEN_VPD=1 +incdir+#{Pathname.new(rtl_top).dirname} -debug_access+all -PP"
  puts
  puts 'Copy the following files (produced by vcs) to simulation/<target>/synopsys/. within your Origen application:'
  puts
  puts '  simv'
  puts '  simv.daidir'
  puts
  puts '-----------------------------------------------------------'
  puts 'Icarus Verilog'
  puts '-----------------------------------------------------------'
  puts
  puts 'Compile the VPI extension using the following command:'
  puts
  puts "  cd #{output_directory} && #{ENV['ORIGEN_SIM_IVERILOG_VPI'] || 'iverilog-vpi'} *.c --name=origen && cd #{Pathname.pwd}"
  puts
  puts 'Add the following to your build script (AND REMOVE ANY OTHER TESTBENCH!):'
  puts
  puts "  #{output_directory}/origen.v \\"
  puts '  -o origen.vvp \\'
  puts '  -DORIGEN_VCD'
  puts
  puts 'Here is an example which may work for the file you just parsed (add additional source dirs with more -I options at the end if required):'
  puts
  puts "  #{ENV['ORIGEN_SIM_IVERILOG'] || 'iverilog'} #{rtl_top} #{output_directory}/origen.v -o origen.vvp -DORIGEN_VCD -I #{Pathname.new(rtl_top).dirname}"
  puts
  puts 'Copy the following files (produced by iverilog) to simulation/<target>/icarus/. within your Origen application:'
  puts
  puts "  #{output_directory}/origen.vpi"
  puts '  origen.vvp'
  puts
  puts '-----------------------------------------------------------'
  puts
  puts 'Testbench and VPI extension created!'
  puts
  puts 'This file can be imported into an Origen top-level DUT model to define the pins:'
  puts
  puts "  #{output_directory}/#{rtl_top_module}.rb"
  puts
  puts 'See above for what to do now to create an Origen-enabled simulation object for your particular simulator.'
  puts
end
