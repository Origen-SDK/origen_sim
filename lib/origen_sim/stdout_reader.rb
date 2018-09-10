require 'thread'
module OrigenSim
  class StdoutReader < Thread
    attr_reader :socket, :logged_errors

    def initialize(socket)
      @socket = socket
      @continue = true
      @logged_errors = false
      super do
        begin
          while @continue
            line = @socket.gets
            if line
              line = line.chomp
              if OrigenSim.error_strings.any? { |s| line =~ /#{s}/i } &&
                 !OrigenSim.error_string_exceptions.any? { |s| line =~ /#{s}/i }
                @logged_errors = true
                Origen.log.error "(STDOUT): #{line}"
              elsif OrigenSim.warning_strings.any? { |s| line =~ /#{s}/i } &&
                    !OrigenSim.warning_string_exceptions.any? { |s| line =~ /#{s}/i }
                Origen.log.warn line
              else
                if OrigenSim.verbose? ||
                   OrigenSim.log_strings.any? { |s| line =~ /#{s}/i }
                  Origen.log.info line
                else
                  Origen.log.debug line
                end
              end
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
  end
end
