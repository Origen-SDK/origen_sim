require 'origen_testers/api'
module OrigenTesters
  module API
    # Returns true if the tester is an instance of OrigenSim::Tester,
    # otherwise returns false
    def sim?
      is_a?(OrigenSim::Tester)
    end
    alias_method :simulator?, :sim?

    def sim_capture(*args)
      yield
    end
  end
end
