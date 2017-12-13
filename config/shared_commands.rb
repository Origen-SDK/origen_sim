# The requested command is passed in here as @command
case @command

when 'generate'
  $use_fast_probe_depth = false
  @application_options << ["--fast", "Fast simulation, minimum probe depth"]
  $use_fast_probe_depth = true if ARGV.include?('--fast')

else
#  @plugin_commands << <<-EOT
#  EOT

end
