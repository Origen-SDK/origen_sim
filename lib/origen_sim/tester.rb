module OrigenSim
  class Tester
    include OrigenTesters::VectorBasedTester

    attr_reader :simulator

    def initialize
      @simulator = Simulator.new
    end
  end


  class Simulator
    require "socket"
    include Origen::Callbacks

    def before_pattern(name)
      server = UNIXServer.new('/tmp/simple.sock')

      Origen.log.info "Starting simulator..."
      @socket = server.accept
      puts "Yo"
    end

    def on_origen_shutdown
      puts "FFFFFUUUUUUUUUUUUUUUUUUUUCK"
      @socket.close if @socket
    end
  end
end
