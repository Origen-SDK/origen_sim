module OrigenSim
  class Tester
    include OrigenTesters::VectorBasedTester

    def put(msg)
      OrigenSim.simulator.put(msg)
    end

    def get
      OrigenSim.simulator.get
    end

    # Blocks the Origen process until the simulator indicates that it has
    # processed all operations up to this point
    def sync_up
      OrigenSim.simulator.sync_up
    end

    def set_timeset(name, period_in_ns)
      super
      put("1^#{period_in_ns}")
    end

    # Applies the current state of all pins to the simulation
    def put_all_pin_states
      dut.pins.each { |name, pin| pin.update_simulation }
    end

    # This method intercepts vector data from Origen, removes white spaces and compresses repeats
    def push_vector(options)
      unless options[:timeset]
        puts 'No timeset defined!'
        puts 'Add one to your top level startup method or target like this:'
        puts '$tester.set_timeset("nvmbist", 40)   # Where 40 is the period in ns'
        exit 1
      end
      put("3^#{options[:repeat] || 1}")
    end
  end
end
