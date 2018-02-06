case @command

when "sim:build", "origen_sim:build"
  require "#{Origen.root!}/lib/origen_sim/commands/build"
  exit 0

else
  @global_commands << <<-EOT
 sim:build    Build an Origen testbench and simulator extension for a given design
  EOT

end
