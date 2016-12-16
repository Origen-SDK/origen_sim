require 'socket'
module OrigenSim
  # Responsible for managing and communicating with the simulator
  # process, a single instance of this class is instantiated as
  # OrigenSim.simulator
  class Simulator
    include Origen::PersistentCallbacks

    attr_reader :socket, :failed

    def before_pattern(name)
      if enabled?
        @enabled = true
        # When running pattern back-to-back, only want to launch the simulator the
        # first time
        unless socket
          server = UNIXServer.new(socket_id)

          @sim_pid = spawn("rake sim[#{socket_id}]")
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
        end
      end
    end

    def on_origen_shutdown
      if enabled?
        Origen.log.info 'Shutting down simulator...'
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

    def enabled?
      @enabled || (tester && tester.is_a?(OrigenSim::Tester))
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
