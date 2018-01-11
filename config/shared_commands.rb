# The requested command is passed in here as @command
case @command

when 'generate'
  $use_fast_probe_depth = false
  @application_options << ["--fast", "Fast simulation, minimum probe depth"]
  $use_fast_probe_depth = true if ARGV.include?('--fast')

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
