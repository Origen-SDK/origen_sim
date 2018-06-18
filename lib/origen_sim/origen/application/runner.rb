require 'origen/application/runner'
module Origen
  class Application
    class Runner
      # When multiple patterns are requested via the command line with the LSF option,
      # Origen will split it into separate jobs for each pattern. However, if the --flow
      # option is also supplied in that case, then the user will want all the patterns to
      # execute as a single job on the LSF, this hack to Origen makes that happen.
      alias_method :orig_expand_lists_and_directories, :expand_lists_and_directories
      def expand_lists_and_directories(files, options = {})
        if (options[:lsf] && OrigenSim.flow) && !Origen.running_remotely?
          Array(Array(files).join(' '))
        else
          orig_expand_lists_and_directories(files, options)
        end
      end
    end
  end
end
