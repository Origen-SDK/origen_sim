require 'origen/pins/pin'
module Origen
  module Pins
    # Override the Origen pin model so we can hook into all changes to pin states
    class Pin
      alias_method :_orig_set_value, :set_value
      def set_value(val)
        ret = _orig_set_value(val)
        update_simulation if simulation_running?
        ret
      end

      alias_method :_orig_set_state, :set_state
      def set_state(val)
        ret = _orig_set_state(val)
        update_simulation if simulation_running?
        ret
      end

      alias_method :_orig_state=, :state=
      def state=(val)
        ret = _orig_state = (val)
        update_simulation if simulation_running?
        ret
      end

      def simulation_running?
        tester && tester.is_a?(OrigenSim::Tester)
      end

      # Applies the current pin state to the simulation, this is triggered everytime
      # the pin state or value changes
      def update_simulation
        case state
          when :drive
            tester.put("2^#{id}^#{value}")
          when :compare
          when :dont_care
          when :capture
          when :drive_very_high, :drive_mem, :expect_mem, :compare_midband
            fail "Simulation of pin state #{state} is not implemented yet!"
          else
            fail "Simulation of pin state #{state} is not implemented yet!"
        end
      end
    end
  end
end
