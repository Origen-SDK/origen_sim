require 'thread'
module OrigenSim
  class StdoutReader < Thread
    attr_reader :socket, :logged_errors

    def initialize(socket, simulator)
      @socket = socket
      @continue = true
      @logged_errors = false
      super do
        begin
          while @continue
            line = @socket.gets
            if line
              line = line.chomp
              # If line has been sent from Origen for logging
              # https://rubular.com/r/xTrRbwb65g230K
              if line =~ /^!(\d)!\[((\s|\d)+,)?((\s|\d)+)\]\s*(.*)/
                if Regexp.last_match(3)
                  time_in_sim_units = (Regexp.last_match(3).to_i << 32) | Regexp.last_match(4).to_i
                  time_in_ns = simulator.send(:simtime_units_to_ns, time_in_sim_units)
                else
                  # Messages sent from the Origen testbench already have a timestamp in ns
                  time_in_ns = Regexp.last_match(4).to_i
                end
                msg = "#{time_in_ns}".rjust(11) + ' ns: ' + Regexp.last_match(6)

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
