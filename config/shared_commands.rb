# The requested command is passed in here as @command
case @command

when 'generate'
  $use_fast_probe_depth = false
  @application_options << ["--fast", "Fast simulation, minimum probe depth"]
  $use_fast_probe_depth = ARGV.include?('--fast')

  @application_options << ["--sim_capture", "Update sim captures (ignored when not running a simulation)"]
  Origen.app!.update_sim_captures = ARGV.include?('--sim_capture')

  @application_options << ["--flow NAME", "Simulate multiple patterns back-back within a single simulation with the given name", ->(options, name) { OrigenSim.flow = name }]

when "sim:ci", "origen_sim:ci"
  require "#{Origen.root!}/lib/origen_sim/commands/ci"
  exit 0

when "sim:co", "origen_sim:co"
  require "#{Origen.root!}/lib/origen_sim/commands/co"
  exit 0

else
  @plugin_commands << <<-EOT
 sim:ci       Checkin a simulation snapshot
 sim:co       Checkout a simulation snapshot
  EOT

end
