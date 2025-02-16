# The requested command is passed in here as @command
case @command

when 'generate', 'program'
  $use_fast_probe_depth = false
  @application_options << ["--fast", "Fast simulation, minimum probe depth"]
  $use_fast_probe_depth = ARGV.include?('--fast')

  @application_options << ["--sim_capture", "Update sim captures (ignored when not running a simulation)", ->(options) {
    Origen.app!.update_sim_captures = true
  }]

  unless @command == 'program'
    @application_options << ["--flow NAME", "Simulate multiple patterns back-back within a single simulation with the given name", ->(options, name) {
      OrigenSim.flow = name
    }]
  end

  @application_options << ["--socket_dir PATH", "Specify the directory to be used for creating the Origen -> simulator communication socket (/tmp by default) ", ->(options, path) {
    FileUtils.mkdir_p(path) unless File.exist?(path)
    path = Pathname.new(path)
    path = path.realpath.to_s
    OrigenSim.socket_dir = path
  }]

  @application_options << ["--max_errors VALUE", Integer, "Override the maximum number of errors allowed in a simulation before aborting ", ->(options, value) {
    OrigenSim.max_errors = value
  }]

when "sim:ci", "origen_sim:ci"
  require "#{Origen.root!}/lib/origen_sim/commands/ci"
  exit 0

when "sim:co", "origen_sim:co"
  require "#{Origen.root!}/lib/origen_sim/commands/co"
  exit 0

when "sim:pack"
  require "#{Origen.root!}/lib/origen_sim/commands/pack"
  OrigenSim::Commands::Pack.pack
  exit 0

when "sim:unpack"
  require "#{Origen.root!}/lib/origen_sim/commands/pack"
  OrigenSim::Commands::Pack.unpack
  exit 0

when "sim:run"
  OrigenSim.run_source(ARGV[0])
  exit 0

#when "sim:list"
#  require "#{Origen.root!}/lib/origen_sim/commands/pack"
#  OrigenSim::Commands::Pack.list
#  exit 0

else
  @plugin_commands << <<-EOT
 sim:ci       Checkin a simulation snapshot
 sim:co       Checkout a simulation snapshot
 sim:pack     Packs the snapshot into a compressed directory
 sim:unpack   Unpacks a snapshot
  EOT
 # sim:list     List the available snapshot packs
  
 if OrigenTesters.respond_to?(:decompile)
  @plugin_commands << <<-EOT
 sim:run      Simulates the given source without using any of Origen's 'startup' collateral.
              Requires: a decompiler for the given source and timing information setup beforehand. 
  EOT
 end

end
