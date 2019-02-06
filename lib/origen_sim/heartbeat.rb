require 'thread'
module OrigenSim
  class Heartbeat < Thread
    attr_reader :socket, :simulation

    # Can't use this with threads currently because Byebug pauses the sleep,
    # during a breakpoint, which means that the simulator is killed.
    # Currently working around via a forked process implementation instead
    # whenever this is set to false.
    THREADSAFE = false

    def initialize(simulation, socket)
      @simulation = simulation
      @socket = socket
      @continue = true
      super do
        while @continue
          begin
            socket.write("OK\n")
          rescue Errno::EPIPE => e
            exit 0 if simulation.ended
            if simulation.monitor_running?
              Origen.log.error 'Communication with the simulation monitor has been lost (though it seems to still be running)!'
            else
              Origen.log.error 'The simulation monitor has stopped unexpectedly!'
            end
            exit 1
          end
          sleep 5
        end
      end
    end

    def stop
      @continue = false
    end
  end
end
