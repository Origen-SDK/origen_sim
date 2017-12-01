# The requested command is passed in here as @command
case @command

when 'generate'
  Origen.log.info 'FAST SIMULATION'
  $use_fast_probe_depth = false
  @application_options << ["--fast", "Fast simulation, minimum probe depth"]
  $use_fast_probe_depth = true if ARGV.include?('--fast')

when "origen_sim:build", "sim:build"
  require "origen_sim/commands/build"
  exit 0

else
  @plugin_commands << <<-EOT
 sim:build       Build the simulation object for the current/given target
  EOT

end
