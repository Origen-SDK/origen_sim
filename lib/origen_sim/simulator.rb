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
        unless socket
          server = UNIXServer.new(socket_id)
          Origen.log.info 'Starting simulator...'
          system "rake sim[#{socket_id}]"
          timeout("FAILED_TO_RESPOND", 5) do
            Origen.log.info 'Pinging simulator...'
            @socket = server.accept
          end
          if @socket.readline.strip == "FAILED_TO_RESPOND"
            Origen.log.error "Simulator failed to respond"
            @failed = true
            exit
          end
          @enabled = true
        end
      else
        @enabled = false
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

    def timeout(message, wait_in_s)
      fork do
        sleep wait_in_s
        UNIXSocket.new(socket_id).puts(message)
      end
      yield
    end
  end
end
