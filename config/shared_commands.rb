# The requested command is passed in here as @command
case @command

when 'generate'
  $use_fast_probe_depth = false
  @application_options << ["--fast", "Fast simulation, minimum probe depth"]
  $use_fast_probe_depth = ARGV.include?('--fast')
  @application_options << ["--sim_capture", "Update sim captures (ignored when not running a simulation)"]
  Origen.app!.update_sim_captures = ARGV.include?('--sim_capture')

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
 sim:list     List the available snapshot packs
  EOT

end
