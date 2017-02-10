# The requested command is passed in here as @command
case @command

when "origen_sim:build", "sim:build"
  require "origen_sim/commands/build"
  exit 0
else
  @plugin_commands << <<-EOT
 sim:build       Build the simulation object for the current/given target
  EOT

end
