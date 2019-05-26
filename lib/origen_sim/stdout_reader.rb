require 'thread'
module OrigenSim
  class StdoutReader < Thread
    attr_reader :socket, :logged_errors

    def initialize(socket, simulator)
      @socket = socket
      @continue = true
      @logged_errors = false
      @last_message_at = Time.now
      super do
        begin
          line = ''
          while @continue
            loop do
              out = @socket.gets
              if out.nil?
                line += ''
                break
              end

              unless line.empty?
                # If there's already stuff in the current line,
                # remove the VPI cruft and leave just the remainder of the message.
                out = out.split(' ', 2)[-1]
                puts out.yellow.underline
              end

              if out.chomp.end_with?(OrigenSim::Simulator::MULTIPART_LOGGER_TOKEN)
                # Part of a multipart message. Add this to the current line
                # and grab the next piece.
                line += out.chomp.gsub(OrigenSim::Simulator::MULTIPART_LOGGER_TOKEN, '')
              else
                # Either a single message or a the end of a multi-part message.
                # Add this to the line break to print the output to the console.
                line += out
                break
              end
            end

            if line
              line = line.chomp
              # If line has been sent from Origen for logging
              # https://rubular.com/r/1czQZnlhBq9YtK
              if line =~ /^!(\d)!\[\s*((\d+),)?\s*(\d+)\]\s*(.*)/
                if Regexp.last_match(3)
                  time_in_sim_units = (Regexp.last_match(3).to_i << 32) | Regexp.last_match(4).to_i
                  time_in_ns = simulator.send(:simtime_units_to_ns, time_in_sim_units)
                else
                  # Messages sent from the Origen testbench already have a timestamp in ns
                  time_in_ns = Regexp.last_match(4).to_i
                end
                msg = "#{time_in_ns}".rjust(11) + ' ns: ' + Regexp.last_match(5)

                Origen.log.send(Simulator::LOG_CODES_[Regexp.last_match(1).to_i], msg, from_origen_sim: true)

                simulator.send(:max_error_abort) if line =~ /!MAX_ERROR_ABORT!/
              else
                if OrigenSim.error_strings.any? { |s| s.is_a?(Regexp) ? s.match?(line) : line =~ /#{s}/i } &&
                   !OrigenSim.error_string_exceptions.any? { |s| s.is_a?(Regexp) ? s.match?(line) : line =~ /#{s}/i }
                  @logged_errors = true
                  Origen.log.error "(STDOUT): #{line}", from_origen_sim: true
                elsif OrigenSim.warning_strings.any? { |s| s.is_a?(Regexp) ? s.match?(line) : line =~ /#{s}/i } &&
                      !OrigenSim.warning_string_exceptions.any? { |s| s.is_a?(Regexp) ? s.match?(line) : line =~ /#{s}/i }
                  Origen.log.warn line, from_origen_sim: true
                else
                  if OrigenSim.verbose? ||
                     OrigenSim.log_strings.any? { |s| s.is_a?(Regexp) ? s.match?(line) : line =~ /#{s}/i }
                    Origen.log.info line, from_origen_sim: true
                  else
                    Origen.log.debug line, from_origen_sim: true
                  end
                end
              end
              line = ''
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
