require 'socket'
require 'io/wait'
require 'origen_sim/heartbeat'
module OrigenSim
  # Responsible for managing each individual simulation that is run in an
  # Origen thread e.g. If multiple patterns are run in separate simulations, then one
  # instance of this class will exist for each one.
  #
  # It is primarily responsible for all communications with the simulation and capturing
  # log output and errors.
  class Simulation
    attr_reader :view_wave_command, :id

    attr_accessor :logged_errors, :error_count, :failed_to_start, :completed_cleanly
    attr_accessor :pid, :stderr_logged_errors
    # Returns the communication socket used for sending commands to the Origen VPI running
    # in the simulation process
    attr_reader :socket

    def initialize(id, view_wave_command)
      @id = id
      @view_wave_command = view_wave_command
      @completed_cleanly = false
      @failed_to_start = false
      @logged_errors = false
      @stderr_logged_errors = false
      @error_count = 0
      @socket_ids = {}

      @server = UNIXServer.new(socket_id) # Socket used to send Origen -> Verilog commands
      @server_stdout = UNIXServer.new(socket_id(:stdout))
      @server_stderr = UNIXServer.new(socket_id(:stderr))
      @server_heartbeat = UNIXServer.new(socket_id(:heartbeat))
    end

    def failed?(in_progress = false)
      failed = stderr_logged_errors || logged_errors || failed_to_start || error_count > 0
      if in_progress
        failed
      else
        failed || !completed_cleanly
      end
    end

    def log_results(in_progress = false)
      if failed?(in_progress)
        if failed_to_start
          Origen.log.error 'The simulation failed to start!'
        else
          if in_progress
            Origen.log.error "The simulation has #{error_count} error#{error_count > 1 ? 's' : ''}!" if error_count > 0
          else
            Origen.log.error "The simulation failed with #{error_count} errors!" if error_count > 0
          end
          Origen.log.error 'The simulation log reported errors!' if logged_errors
          Origen.log.error 'The simulation stderr reported errors!' if stderr_logged_errors
          Origen.log.error 'The simulation exited early!' unless completed_cleanly || in_progress
        end
      else
        if in_progress
          Origen.log.success 'The simulation is passing!'
        else
          Origen.log.success 'The simulation passed!'
        end
      end
    end

    # Provide a heartbeat to let the parallel Ruby process in charge of the simulator
    # know that the master Origen process is still alive. If the Origen process crashes and leaves
    # the simulator running, the child process will automatically reap it after a couple of missed
    # heartbeats.
    def start_heartbeat
      @heartbeat = @server_heartbeat.accept
      @pid = @heartbeat.gets.chomp.to_i
      @heartbeat_thread = Heartbeat.new(@heartbeat)
    end

    def stop_heartbeat
      @heartbeat_thread.stop
    end

    # Open the communication channels with the simulator
    def open
      start_heartbeat
      @stdout = @server_stdout.accept
      @stderr = @server_stderr.accept
      @socket = @server.accept
      @opened = true
    end

    # Close all communication channels with the simulator
    def close
      return unless @opened
      stop_heartbeat
      @heartbeat.close
      @socket.close
      @stderr.close
      @stdout.close
      File.unlink(socket_id(:heartbeat)) if File.exist?(socket_id(:heartbeat))
      File.unlink(socket_id) if File.exist?(socket_id)
      File.unlink(socket_id(:stderr)) if File.exist?(socket_id(:stderr))
      File.unlink(socket_id(:stdout)) if File.exist?(socket_id(:stdout))
    end

    def read_sim_output
      while @stdout.ready?
        line = @stdout.gets.chomp
        if OrigenSim.error_strings.any? { |s| line =~ /#{s}/ } &&
           !OrigenSim.error_string_exceptions.any? { |s| line =~ /#{s}/ }
          @logged_errors = true
          Origen.log.error "(STDOUT): #{line}"
        else
          if OrigenSim.verbose? ||
             OrigenSim.log_strings.any? { |s| line =~ /#{s}/ }
            Origen.log.info line
          else
            Origen.log.debug line
          end
        end
      end
      while @stderr.ready?
        line = @stderr.gets.chomp
        if OrigenSim.fail_on_stderr && !line.empty? &&
           !OrigenSim.stderr_string_exceptions.any? { |s| line =~ /#{s}/ }
          # We're failing on stderr, so print its results and log as errors if its not an exception.
          @stderr_logged_errors = true
          Origen.log.error "(STDERR): #{line}"
        elsif OrigenSim.verbose?
          # We're not failing on stderr, or the string in stderr is an exception.
          # Print the string as regular output if verbose is set, otherwise just ignore.
          Origen.log.info line
        end
      end
    end

    # Returns true if the simulation is running
    def running?
      return false unless pid
      begin
        Process.getpgid(pid)
        true
      rescue Errno::ESRCH
        false
      end
    end

    def socket_id(type = nil)
      @socket_ids[type] ||= "/tmp/#{socket_number}#{type}.sock"
    end

    private

    def socket_number
      @socket_number ||= (Process.pid.to_s + Time.now.to_f.to_s).sub('.', '')
    end
  end
end
