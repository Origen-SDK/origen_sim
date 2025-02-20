require 'optparse'
require 'origen_sim'
require_relative '../../../config/version'
require 'origen_verilog'

options = {
  incl_files:              [],
  source_dirs:             [],
  testbench_name:          'origen',
  defines:                 [],
  user_details:            {},
  initial_pin_states:      {},
  forced_pin_types:        {},
  verilog_top_output_name: 'origen',
  file_type:               :v,
  power_pins:              [],
  ground_pins:             [],
  virtual_pins:            [],
  other_pins:              [],
  passthrough:             [],
}

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
  opts.on('--sv', 'Generate a .sv file instead of a .v file.') { |t| options[:sv] = t; options[:file_type] = :sv }
  opts.on('--wreal', 'Enable real number modeling support on DUT pins defined as real wires (wreal)') { |t| options[:wreal] = t }
  opts.on('--wrealavg', 'Enable real number modeling support on DUT pins defined as real wires - averaged (wrealavg)') { |t| options[:wrealavg] = t }
  opts.on('--verilog_top_output_name NAME', 'Renames the output filename from origen.v to NAME.v') do |name|
    options[:verilog_top_output_name] = name
  end
  opts.on('--define MACRO', 'Specify a compiler define') do |macro|
    options[:defines] << macro
  end
  opts.on('--init_pin_state PIN_AND_STATE', 'Specify how the pins should be initialized.') do |pin_and_state|
    name, state = pin_and_state.split(':')

    # Make sure that we recognize the pin state option before building.
    unless OrigenSim::INIT_PIN_STATE_MAPPING.include?(state)
      fail "Provide state '#{state}' to --init_pin_state pin_and_state not recognized!"
    end
    (options[:initial_pin_states])[name.to_sym] = OrigenSim::INIT_PIN_STATE_MAPPING[state]
  end
  opts.on('--force_pin_type PIN_AND_TYPE', 'Overwrite the pin driver discerned from DUT module') do |pin_and_type|
    name, type = pin_and_type.split(':')
    (options[:forced_pin_types])[name] = OrigenSim::FORCE_PIN_TYPES_MAPPING[type]
  end
  opts.on('--power_pins PINS_AND_REGEXES', 'Using pin names or regexes, indicate which pins are power pins, seperated by tildas') do |str_or_regex|
    options[:power_pins] << str_or_regex
  end
  opts.on('--ground_pins PINS_AND_REGEXES', 'Using pin names or regexes, indicate which pins are ground pins, seperated by tildas') do |str_or_regex|
    options[:ground_pins] << str_or_regex
  end
  opts.on('--virtual_pins PINS_AND_REGEXES', 'Using pin names or regexes, indicate which pins are virtual pins, seperated by tildas') do |str_or_regex|
    options[:virtual_pins] << str_or_regex
  end
  opts.on('--other_pins PINS_AND_REGEXES', 'Using pin names or regexes, indicate which pins are \'other\' pins, seperated by tildas') do |str_or_regex|
    options[:other_pins] << str_or_regex
  end
  opts.on('--include FILE', 'Specify files to include in the top verilog file.') { |f| options[:incl_files] << f }
  opts.on('--vendor VENDOR', 'Specify the target vendor (Cadence, Synopsis, Icarus') { |v| options[:vendor] = v.downcase.to_sym }
  opts.on('--passthrough SWITCHES', 'Raw switches that will be ignored by OrigenSim, but appear in the final build command') { |s| options[:passthrough] << s }

  # Specifying snapshot details
  opts.on('--device_name NAME', '(Snapshot Detail) Specify a device name') { |n| options[:device_name] = n }
  opts.on('--testbench_version VER', '(Snapshot Detail) Specify a version of the testbench this snapshot was built from') { |v| options[:testbench_version] = v }
  opts.on('--revision REV', '(Snapshot Detail) Specify a revision of the snapshot') { |r| options[:revision] = r }
  opts.on('--revision_note REV_NOTE', '(Snapshot Detail) Specify a brief note on this revision of the snapshot') { |n| options[:revision_note] = n }
  opts.on('--author AUTHOR', '(Snapshot Detail) Specify the author of the snapshot (default is just Origen.current_user)') { |a| options[:author] = a }

  opts.on('--finish_signal FINISH_SIGNAL', 'Specify the finish signal') { |f| options[:finish_signal] = f }
  opts.on('--debug_module_name MOD_NAME', 'Specify the debug module name') { |d| options[:debug_module_name] = d }

  # User-defined snapshot details
  opts.on('--USER_DETAIL NAME_AND_VALUE', 'Specify custom user-defined details to build into the snapshot details. Format as NAME:VALUE, e.g.: \'--USER_DETAIL BUILD_TYPE:RTL\'') do |name_and_value|
    name, value = name_and_value.split(':')

    unless name.upcase == name
      Origen.log.warning "Non-capitalized user detail '#{name}' was given!"
      Origen.log.warning 'OrigenSim forces the Verilog practice that parameters should be capitalized.'
      Origen.log.warning "The parameter '#{name.upcase}' will be used instead"
      name.upcase!
    end
    (options[:user_details])[name] = value
  end
  opts.on('-d', '--debugger', 'Enable the debugger') {  options[:debugger] = true }
  app_options.each do |app_option|
    opts.on(*app_option) {}
  end
  opts.separator ''
  opts.on('-h', '--help', 'Show this message') { puts opts; exit 0 }
end

build_cmd = 'origen sim:build ' + ARGV.map do |arg|
  # Command-line-ify some of the argument values.
  if arg.include?(' ') || (arg[0] == '/' && arg[1] == '/' && arg.size > 1)
    # if the argument is a string, wrap it in quotes.
    # Likewise, if the argument looks like a regex, wrap it in quotes as well.
    arg = "\"#{arg}\""
  end

  # If the argument includes any !s, escape them
  arg = arg.gsub('!', '\!')

  arg
end.join(' ')
opt_parser.parse! ARGV

options.select { |k, v| [:power_pins, :ground_pins, :virtual_pins, :other_pins].include?(k) }.each do |k, pins_or_regexes|
  options[k] = pins_or_regexes.map { |input| input.split('~') }.flatten.map do |p|
    if p.start_with?('/') && p.end_with?('/')
      Regexp.new(p[1..-2])
    else
      p
    end
  end
end

options[:forced_pin_types] = options[:forced_pin_types].map do |pin_or_regex, type|
  if pin_or_regex.start_with?('/') && pin_or_regex.end_with?('/')
    # run this as a regex, not as a single pin name
    # Cut out the leading / and trailing / characters though
    [Regexp.new(pin_or_regex.to_s[1..-2]), type]
  else
    [pin_or_regex, type]
  end
end.to_h

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
  puts "Sorry, couldn't find any Verilog module declarations in that file (this could be due to a parse error)"
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

mod.to_top_level(options) # Creates dut

# Update the pins with any settings from the command line
options[:initial_pin_states].each do |pin, state|
  dut.pins(pin).meta[:origen_sim_init_pin_state] = state
end

if $_testing_build_return_dut_
  dut

else

  output_directory = options[:output] || Origen.config.output_directory
  output_name = options[:sv] ? "#{options[:verilog_top_output_name]}.sv" : "#{options[:verilog_top_output_name]}.v"

  Origen.app.runner.launch action:            :compile,
                           files:             "#{Origen.root!}/templates/rtl_v/origen.v.erb",
                           output_file_name:  output_name,
                           output:            output_directory,
                           check_for_changes: false,
                           quiet:             true,
                           preserve_target:   true,
                           options:           {
                             vendor:            options[:vendor],
                             top:               dut.name,
                             testbench_name:    options[:testbench_name],
                             incl:              options[:incl_files],
                             device_name:       options[:device_name],
                             revision:          options[:revision],
                             revision_note:     options[:revision_note],
                             parent_tb_version: options[:testbench_version],
                             user_details:      options[:user_details],
                             author:            options[:author],
                             build_cmd:         build_cmd,
                             file_type:         options[:file_type],
                             testbench:         options[:testbench_name] || "origen",
                             top_level_name:    options[:top_level_name] || "dut",
                             finish_signal:     options[:finish_signal] || "finish",
                             debug_module_name: options[:debug_module_name] || "debug",
                           }

  Origen.app.runner.launch action:            :compile,
                           files:             "#{Origen.root!}/ext",
                           output:            output_directory,
                           check_for_changes: false,
                           quiet:             true,
                           options:           options

  dut.export(rtl_top_module, dir: "#{output_directory}", namespace: nil)

  SYNOPSYS_SWITCHES = %W(
    #{output_directory}/#{output_name}
    #{output_directory}/bridge.c
    #{output_directory}/client.c
    -P\ #{output_directory}/origen_tasks.tab
    -CFLAGS\ "-std=c99 -DORIGEN_VCS"
    +vpi
    #{output_directory}/origen.c
    +define+ORIGEN_VCS
    -debug_access+all
    -timescale=1ns/1ns
    -v2005
    -full64
  )

  if options[:wreal]
    SYNOPSYS_SWITCHES += %w(
      +define+ORIGEN_WREAL
      -realport
      -sverilog
      -wreal\ res_max
    )
  end

  if options[:wrealavg]
    SYNOPSYS_SWITCHES += %w(
      +define+ORIGEN_WREALAVG
      -realport
      -sverilog
      -lca
      -xlrm\ coerce_nettype
    )
  end

  SYNOPSYS_DVE_SWITCHES = SYNOPSYS_SWITCHES + %w(
    +define+ORIGEN_VPD
  )

  SYNOPSYS_VERDI_SWITCHES = SYNOPSYS_SWITCHES + %W(
    +define+ORIGEN_FSDB
    -kdb
    -P\ #{ENV['VERDI_HOME'] || '$VERDI_HOME'}/share/PLI/VCS/LINUX64/novas.tab
    #{ENV['VERDI_HOME'] || '$VERDI_HOME'}/share/PLI/VCS/LINUX64/pli.a
  )

  CADENCE_SWITCHES = %W(
    #{output_directory}/#{output_name}
    #{output_directory}/*.c
    -ccargs\ "-std=c99"
    -top\ origen
    -elaborate
    -snapshot\ origen
    -access\ +rw
    -timescale\ 1ns/1ns
  )

  if options[:wreal]
    CADENCE_SWITCHES += %w(
      +define+ORIGEN_WREAL
      -ams
    )
  end

  if options[:wrealavg]
    CADENCE_SWITCHES += %w(
      +define+ORIGEN_WREALAVG
    )
  end

  puts
  if options[:vendor].nil? || options[:vendor] == :icarus
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
    puts "  #{output_directory}/#{output_name} \\"
    puts '  -o origen.vvp \\'
    puts '  -DORIGEN_VCD'
    puts
    puts 'Here is an example which may work for the file you just parsed (add additional source dirs with more -I options at the end if required):'
    puts
    puts "  #{ENV['ORIGEN_SIM_IVERILOG'] || 'iverilog'} #{rtl_top} #{output_directory}/#{output_name} -o origen.vvp -DORIGEN_VCD -I #{Pathname.new(rtl_top).dirname}"
    puts
    puts 'Copy the following files (produced by iverilog) to simulation/<target>/icarus/. within your Origen application:'
    puts
    puts "  #{output_directory}/origen.vpi"
    puts '  origen.vvp'
  end
  if options[:vendor].nil? || options[:vendor] == :synopsis
    puts
    puts '-----------------------------------------------------------'
    puts 'Synopsys VCS w/ DVE Waveviewer'
    puts '-----------------------------------------------------------'
    puts
    puts 'Add the following to your build script (AND REMOVE ANY OTHER TESTBENCH!):'
    puts
    SYNOPSYS_DVE_SWITCHES.each do |switch|
      puts "  #{switch} \\"
    end
    puts
    puts 'Here is an example which may work for the file you just parsed (add additional +incdir+ options at the end if required):'
    puts
    puts "  #{ENV['ORIGEN_SIM_VCS'] || 'vcs'} #{rtl_top} +incdir+#{Pathname.new(rtl_top).dirname} " + SYNOPSYS_DVE_SWITCHES.join(' ') + (options[:passthrough] ? " #{options[:passthrough].join(' ')}" : '')
    puts
    puts 'Copy the following files (produced by vcs) to simulation/<target>/synopsys/. within your Origen application:'
    puts
    puts '  simv'
    puts '  simv.daidir'
    puts
    puts '-----------------------------------------------------------'
    puts 'Synopsys VCS w/ Verdi Waveviewer'
    puts '-----------------------------------------------------------'
    puts
    puts 'Add the following to your build script (AND REMOVE ANY OTHER TESTBENCH!):'
    puts
    SYNOPSYS_VERDI_SWITCHES.each do |switch|
      puts "  #{switch} \\"
    end
    puts
    puts 'Here is an example which may work for the file you just parsed (add additional +incdir+ options at the end if required):'
    puts
    puts "  #{ENV['ORIGEN_SIM_VCS'] || 'vcs'} #{rtl_top} +incdir+#{Pathname.new(rtl_top).dirname} " + SYNOPSYS_VERDI_SWITCHES.join(' ') + (options[:passthrough] ? " #{options[:passthrough].join(' ')}" : '')
    puts
    puts 'Copy the following files (produced by vcs) to simulation/<target>/synopsys/. within your Origen application:'
    puts
    puts '  simv'
    puts '  simv.daidir'
    puts
    puts '-----------------------------------------------------------'
    puts 'Cadence Incisive (irun)'
    puts '-----------------------------------------------------------'
    puts
    puts 'Add the following to your build script (AND REMOVE ANY OTHER TESTBENCH!):'
  end
  if options[:vendor].nil? || options[:vendor] == :cadence
    puts
    CADENCE_SWITCHES.each do |switch|
      puts "  #{switch} \\"
    end
    puts
    puts 'Here is an example which may work for the file you just parsed (add additional -incdir options at the end if required):'
    puts
    puts "  #{ENV['ORIGEN_SIM_IRUN'] || 'irun'} #{rtl_top} -incdir #{Pathname.new(rtl_top).dirname} " + CADENCE_SWITCHES.join(' ') + (options[:passthrough] ? " #{options[:passthrough].join(' ')}" : '')
    puts
    puts 'Copy the following directory (produced by irun) to simulation/<target>/cadence/. within your Origen application:'
    puts
    puts '  INCA_libs'
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
  end
  puts

end
