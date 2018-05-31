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
    attr_accessor :pid
    # Returns the communication socket used for sending commands to the Origen VPI running
    # in the simulation process
    attr_reader :socket

    def initialize(id, view_wave_command)
      @id = id
      @view_wave_command = view_wave_command
      @completed_cleanly = false
      @failed_to_start = false
      @logged_errors = false
      @error_count = 0
      @socket_ids = {}

      @server = UNIXServer.new(socket_id) # Socket used to send Origen -> Verilog commands
      @server_stdout = UNIXServer.new(socket_id(:stdout))
      @server_stderr = UNIXServer.new(socket_id(:stderr))
      @server_heartbeat = UNIXServer.new(socket_id(:heartbeat))
    end

    def failed?
      logged_errors || failed_to_start || !completed_cleanly || error_count > 0
    end

    def log_results
      if failed?
        if failed_to_start
          Origen.log.error 'The simulation failed to start!'
        else
          if completed_cleanly
            if failed?
              Origen.log.error "The simulation failed with #{error_count} errors!" if error_count > 0
              Origen.log.error 'The simulation log reported errors!' if logged_errors
            end
          else
            Origen.log.error 'The simulation exited early!'
          end
        end
      else
        Origen.log.success 'The simulation passed!'
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
          Origen.log.error line
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
        @logged_errors = true if OrigenSim.fail_on_stderr
        Origen.log.error @stderr.gets.chomp
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
