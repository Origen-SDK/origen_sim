module OrigenSim
  # Responsible for managing and communicating with the simulator
  # process, a single instance of this class is instantiated as
  # OrigenSim.simulator
  class Simulator
    require 'socket'
    include Origen::PersistentCallbacks

    def before_pattern(name)
      if enabled?
        server = UNIXServer.new(socket_id)
        Origen.log.info 'Starting simulator...'
        # @socket = server.accept
        @enabled = true
      else
        @enabled = false
      end
    end

    def on_origen_shutdown
      if enabled?
        Origen.log.info 'Shutting down simulator...'
        @socket.close if @socket
        File.unlink(socket_id) if File.exist?(socket_id)
      end
    end

    def socket_id
      @socket_id ||= "/tmp/#{(Process.pid.to_s + Time.now.to_f.to_s).sub('.', '')}.sock"
    end

    def enabled?
      @enabled || (tester && tester.is_a?(OrigenSim::Tester))
    end
  end
end
