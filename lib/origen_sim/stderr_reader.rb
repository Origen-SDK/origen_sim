require 'thread'
module OrigenSim
  class StderrReader < Thread
    attr_reader :socket, :logged_errors

    def initialize(socket)
      @socket = socket
      @continue = true
      @logged_errors = false
      @last_message_at = Time.now
      super do
        begin
          while @continue
            line = @socket.gets
            if line
              line = line.chomp
              if OrigenSim.fail_on_stderr && !line.empty? &&
                 !OrigenSim.stderr_string_exceptions.any? { |s| s.is_a?(Regexp) ? s.match?(line) : line =~ /#{s}/i }
                # We're failing on stderr, so print its results and log as errors if its not an exception.
                @logged_errors = true
                Origen.log.error "(STDERR): #{line}"
              elsif OrigenSim.verbose?
                Origen.log.info line
              else
                Origen.log.debug line
              end
              @last_message_at = Time.now
            end
          end
        rescue IOError => e
          unless e.message =~ /stream closed/
            raise e
          end
        end
      end
    end

    def stop
      @continue = false
    end

    def time_since_last_message
      Time.now - @last_message_at
    end
  end
end
