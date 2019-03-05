require 'socket'
require 'io/wait'
require 'origen_sim/heartbeat'
require 'origen_sim/stdout_reader'
require 'origen_sim/stderr_reader'
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
    # Returns false when the simulation is running and will be set to true once all instructions
    # have been sent and executed by the simulator and immediately before the end_simulation
    # instruction is sent to the simulator.
    attr_accessor :ended

    attr_reader :log_files

    attr_accessor :max_errors_exceeded

    def initialize(id, view_wave_command)
      @id = id
      @view_wave_command = view_wave_command
      @completed_cleanly = false
      @failed_to_start = false
      @logged_errors = false
      @ended = false
      @error_count = 0
      @socket_ids = {}
      @log_files = []
      @max_errors_exceeded = false

      # Socket used to send Origen -> Verilog commands
      @server = UNIXServer.new(socket_id)

      # Socket used to capture STDOUT from the simulator
      @server_stdout = UNIXServer.new(socket_id(:stdout))
      # Socket used to capture STDERR from the simulator
      @server_stderr = UNIXServer.new(socket_id(:stderr))
      # Socket used to send a heartbeat pulse from Origen to process running the simulator
      @server_heartbeat = UNIXServer.new(socket_id(:heartbeat))
      # Socket used to receive status updates from the process running the simulator
      @server_status = UNIXServer.new(socket_id(:status))
    end

    def failed?(in_progress = false)
      failed = stderr_logged_errors || logged_errors || failed_to_start || error_count > 0
      if in_progress
        failed
      else
        failed || !completed_cleanly
      end
    end

    def logged_errors
      @logged_errors || @stdout_reader.logged_errors
    end

    def stderr_logged_errors
      @stderr_reader.logged_errors
    end

    def log_results(in_progress = false)
      if failed?(in_progress)
        if failed_to_start
          if Origen.debugger_enabled?
            Origen.log.error 'The simulation failed to get underway!'
          else
            Origen.log.error 'The simulation failed to get underway! (run again with -d to see why)'
          end
        else
          if in_progress
            simulator.log("The simulation has #{error_count} error#{error_count > 1 ? 's' : ''}!", :error) if error_count > 0
          else
            Origen.log.error "The simulation failed with #{error_count} errors!" if error_count > 0
            Origen.log.error "The simulation was aborted due to exceeding #{simulator.max_errors} errors!" if max_errors_exceeded
          end
          Origen.log.error 'The simulation log reported errors!' if logged_errors
          Origen.log.error 'The simulation stderr reported errors!' if stderr_logged_errors
          Origen.log.error 'The simulation exited early!' unless completed_cleanly || in_progress
        end
      else
        if in_progress
          simulator.log 'The simulation is passing!', :success
        else
          Origen.log.success 'The simulation passed!'
        end
      end
    end

    def ended=(val)
      # If running the heartbeat from a fork we need to communicate to it that the simulation has
      # ended by writing to a file
      if val == true && !Heartbeat::THREADSAFE
        FileUtils.touch(ended_file)
      else
        @ended = val
      end
    end

    def ended_file
      @ended_file ||= begin
        dir = Origen.root.join('tmp', 'origen_sim', 'ended')
        FileUtils.mkdir_p(dir.to_s)
        dir.join(socket_number).to_s
      end
    end

    # Provide a heartbeat to let the parallel Ruby process in charge of the simulator
    # know that the master Origen process is still alive. If the Origen process crashes and leaves
    # the simulator running, the child process will automatically reap it after a couple of missed
    # heartbeats.
    def start_heartbeat
      @heartbeat = @server_heartbeat.accept
      if Heartbeat::THREADSAFE
        @heartbeat_thread = Heartbeat.new(self, @heartbeat)
      else
        ended_file # Cache this file name before forking
        @heartbeat_pid = fork do
          loop do
            begin
              @heartbeat.write("OK\n")
            rescue Errno::EPIPE => e
              if File.exist?(ended_file)
                FileUtils.rm_f(ended_file)
                exit 0
              else
                if monitor_running?
                  Origen.log.error 'Communication with the simulation monitor has been lost (though it seems to still be running)!'
                else
                  Origen.log.error 'The simulation monitor has stopped unexpectedly!'
                end
                exit 1
              end
            end
            sleep 5
          end
        end
      end
    end

    def stop_heartbeat
      if Heartbeat::THREADSAFE
        @heartbeat_thread.stop
      else
        Process.kill('SIGHUP', @heartbeat_pid)

        # Ensure that the process has stopped before closing the IO pipes
        begin
          Process.waitpid(@heartbeat_pid)
        rescue Errno::ECHILD
          # Heartbeat process has already stopped, so ignore this.
        end
        FileUtils.rm_f(ended_file) if File.exist?(ended_file)
      end
    end

    # Open the communication channels with the simulator
    def open(monitor_pid, timeout)
      @monitor_pid = monitor_pid
      timeout_connection(timeout) do
        start_heartbeat
        @stdout = @server_stdout.accept
        @stderr = @server_stderr.accept
        @status = @server_status.accept
        @stdout_reader = StdoutReader.new(@stdout, simulator)
        @stderr_reader = StderrReader.new(@stderr)

        Origen.log.debug 'The simulation monitor has started'
        Origen.log.debug @status.gets.chomp  # Starting simulator
        Origen.log.debug @status.gets.chomp  # Simulator has started
        response = @status.gets.chomp
        if response =~ /finished/
          abort_connection
        else
          @pid = response.to_i
        end
        # That's all status info done until the simulation process ends, start a thread
        # to wait for that in case it ends before the VPI starts
        Thread.new do
          @status.gets.chomp  # This will block until something is received
          abort_connection
        end
        Origen.log.debug 'Waiting for Origen VPI to start...'

        # This will block until the VPI extension is invoked and connects to the socket
        @socket = @server.accept

        @connection_established = true # Cancels timeout_connection
        if @connection_aborted
          self.failed_to_start = true
          log_results
          exit  # Assume it is not worth trying another pattern in this case, some kind of environment/config issue
        end
        Origen.log.debug 'Origen VPI has started'
      end

      @opened = true
    end

    def timeout_connection(wait_in_s)
      @connection_aborted = false
      @connection_established = false
      Thread.new do
        sleep wait_in_s
        abort_connection # Will do nothing if a successful connection has been made while we were waiting
      end
      yield
    end

    def abort_connection
      # If the Verilog process has not established a connection yet, then make one to
      # release our process and then exit
      unless @connection_established
        @connection_aborted = true
        UNIXSocket.new(socket_id).puts("Time out\n")
      end
    end

    # Close all communication channels with the simulator
    def close
      return unless @opened
      stop_heartbeat
      @stdout_reader.stop
      @stderr_reader.stop
      @heartbeat.close
      @socket.close
      @stderr.close
      @stdout.close
      @status.close
      File.unlink(socket_id(:heartbeat)) if File.exist?(socket_id(:heartbeat))
      File.unlink(socket_id) if File.exist?(socket_id)
      File.unlink(socket_id(:stderr)) if File.exist?(socket_id(:stderr))
      File.unlink(socket_id(:stdout)) if File.exist?(socket_id(:stdout))
      File.unlink(socket_id(:status)) if File.exist?(socket_id(:status))
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

    # Returns true if the simulation monitor process (the one that receives the heartbeat
    # and kills the simulation if it stops) is running
    def monitor_running?
      return false unless @monitor_pid
      begin
        Process.getpgid(@monitor_pid)
        true
      rescue Errno::ESRCH
        false
      end
    end

    def socket_id(type = nil)
      @socket_ids[type] ||= "#{OrigenSim.socket_dir || '/tmp'}/#{socket_number}#{type}.sock"
    end

    private

    def simulator
      tester.simulator
    end

    def socket_number
      @socket_number ||= (Process.pid.to_s + Time.now.to_f.to_s).sub('.', '')
    end
  end
end
