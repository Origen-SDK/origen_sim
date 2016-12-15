module OrigenSim
  class Tester
    include OrigenTesters::VectorBasedTester

    def simulator
      OrigenSim.simulator
    end
  end
end
