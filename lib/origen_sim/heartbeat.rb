require 'thread'
module OrigenSim
  class Heartbeat < Thread
    attr_reader :socket

    # Can't use this with threads currently because Byebug pauses the sleep,
    # during a breakpoint, which means that the simulator is killed.
    # Currently working around via a forked process implementation instead
    # whenever this is set to false.
    THREADSAFE = false

    def initialize(socket)
      @socket = socket
      @continue = true
      super do
        while @continue
          socket.write("OK\n")
          sleep 5
        end
      end
    end

    def stop
      @continue = false
    end
  end
end
