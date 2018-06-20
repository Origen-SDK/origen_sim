require 'thread'
require 'io/wait'
module OrigenSim
  class StderrReader < Thread
    attr_reader :socket, :logged_errors

    def initialize(socket)
      @socket = socket
      @continue = true
      @logged_errors = false
      super do
        while @continue
          while @socket.ready?
            line = @socket.gets.chomp
            if OrigenSim.fail_on_stderr && !line.empty? &&
               !OrigenSim.stderr_string_exceptions.any? { |s| line =~ /#{s}/ }
              # We're failing on stderr, so print its results and log as errors if its not an exception.
              @logged_errors = true
              Origen.log.error "(STDERR): #{line}"
            elsif OrigenSim.verbose?
              Origen.log.info line
            else
              Origen.log.debug line
            end
          end
        end
      end
    end

    def stop
      @continue = false
    end
  end
end
