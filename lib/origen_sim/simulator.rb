require 'socket'
module OrigenSim
  # Responsible for managing and communicating with the simulator
  # process, a single instance of this class is instantiated as
  # OrigenSim.simulator
  class Simulator
    include Origen::PersistentCallbacks

    attr_reader :socket, :failed

    # Send the given message string to the simulator
    def put(msg)
      socket.write(msg + "\n") if socket
    end

    # Get a message from the simulator, will block until one
    # is received
    def get
      socket.readline
    end

    # This will be called at the end of every pattern, make
    # sure the simulator is not running behind before potentially
    # moving onto another pattern
    def pattern_generated(path)
      sync_up
    end

    # Called before every pattern is generated, but we only use it the
    # first time it is called to kick off the simulator process if the
    # current tester is an OrigenSim::Tester
    def before_pattern(name)
      if simulation_tester?
        unless @enabled
          @enabled = true
          # When running pattern back-to-back, only want to launch the simulator the
          # first time
          unless socket
            server = UNIXServer.new(socket_id)

            @sim_pid = spawn("rake sim:run[#{socket_id}]")
            Process.detach(@sim_pid)

            timeout_connection(5) do
              @socket = server.accept
              @connection_established = true
              if @connection_timed_out
                Origen.log.error 'Simulator failed to respond'
                @failed = true
                exit
              end
            end
            data = tester.get
            unless data.strip == 'READY!'
              fail "The simulator didn't start properly!"
            end
          end
        end
        # Apply the pin reset values before the simulation starts
        tester.put_all_pin_states
      end
    end

    def end_simulation
      put('Z^')
    end

    # Blocks the Origen process until the simulator indicates that it has
    # processed all operations up to this point
    def sync_up
      tester.put('Y^')
      data = tester.get
      unless data.strip == 'OK!'
        fail 'Origen and the simulator are out of sync!'
      end
    end

    def on_origen_shutdown
      if @enabled
        Origen.log.info 'Shutting down simulator...'
        sync_up
        end_simulation
        @socket.close if @socket
        File.unlink(socket_id) if File.exist?(socket_id)
        if failed
          Origen.app.stats.report_fail
        else
          Origen.app.stats.report_pass
        end
      end
    end

    def socket_id
      @socket_id ||= "/tmp/#{(Process.pid.to_s + Time.now.to_f.to_s).sub('.', '')}.sock"
    end

    def simulation_tester?
      (tester && tester.is_a?(OrigenSim::Tester))
    end

    def timeout_connection(wait_in_s)
      @connection_timed_out = false
      t = Thread.new do
        sleep wait_in_s
        # If the Verilog process has not established a connection yet, then make one to
        # release our process and then exit
        unless @connection_established
          @connection_timed_out = true
          UNIXSocket.new(socket_id).puts(message)
        end
      end
      yield
    end
  end
end
