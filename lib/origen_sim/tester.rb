module OrigenSim
  # Responsible for interfacing the simulator with Origen
  class Tester
    include OrigenTesters::VectorBasedTester

    def initialize(options = {})
      super()
    end

    def simulator
      OrigenSim.simulator
    end

    def set_timeset(name, period_in_ns)
      super
      simulator.set_period(period_in_ns)
    end

    # This method intercepts vector data from Origen, removes white spaces and compresses repeats
    def push_vector(options)
      unless options[:timeset]
        puts 'No timeset defined!'
        puts 'Add one to your top level startup method or target like this:'
        puts '$tester.set_timeset("nvmbist", 40)   # Where 40 is the period in ns'
        exit 1
      end
      simulator.cycle(options[:repeat] || 1)
    end
  end
end
