require 'thread'
module OrigenSim
  class Heartbeat < Thread
    attr_reader :socket

    def initialize(socket)
      @socket = socket
      @continue = true
      super do
        while @continue
          socket.write("OK\n")
          sleep 0.5
        end
      end
    end

    def stop
      @continue = false
    end
  end
end
