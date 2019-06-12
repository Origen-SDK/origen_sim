require 'origen/pins/pin'
module Origen
  module Pins
    # Override the Origen pin model so we can hook into all changes to pin states
    class Pin
      # The index number that is used to refer to the pin within the simulation
      attr_accessor :simulation_index

      alias_method :_orig_initialize, :initialize
      def initialize(id, owner, options = {})
        _orig_initialize(id, owner, options)
      end

      alias_method :_orig_set_value, :set_value
      def set_value(val)
        ret = _orig_set_value(val)
        update_simulation if simulation_running?
        ret
      end

      alias_method :_orig_set_state, :set_state
      def set_state(state)
        ret = _orig_set_state(state)
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

      def simulator
        OrigenSim.simulator
      end

      # Returns true if the current pin state is different to that last given to the simulator
      def simulator_needs_update?
        return false if state == :dont_care && @simulator_state == :dont_care
        state != @simulator_state || value != @simulator_value
      end

      def reset_simulator_state
        @simulator_state = nil
        @simulator_value = nil
      end

      def driver_net
        @driver_net ||= "#{tester.simulator.testbench_top}.pins.#{rtl_name}"
      end

      alias_method :_orig_drive, :drive
      def drive(*args)
        if _analog_pin_? && simulation_running? && tester.simulator.real?
          tester.poke("#{driver_net}.drive_en", 1)
          tester.poke("#{driver_net}.drive", args.first + 0.0)
        else
          _orig_drive(*args)
        end
      end
      alias_method :write, :drive

      alias_method :_orig_assert, :assert
      def assert(*args)
        if _analog_pin_? && simulation_running? && tester.simulator.real?
          drive_enabled = tester.peek("#{driver_net}.drive_en").to_i
          if drive_enabled == 1
            #tester.poke("#{driver_net}.drive_en", 0)
            #tester.cycle
          end
          measured = tester.peek("#{driver_net}.pin", true)
          # Could implement checking/limits here in future
        else
          _orig_assert(*args)
        end
      end
      alias_method :compare, :assert
      alias_method :expect, :assert
      alias_method :read, :assert
      alias_method :measure, :assert

      def _analog_pin_?
        type == :analog || is_a?(Origen::Pins::PowerPin) || is_a?(Origen::Pins::GroundPin)
      end

      def apply_force
        if force
          simulator.put("2^#{simulation_index}^#{force}")
        end
      end

      # Applies the current pin state to the simulation, this is triggered everytime
      # the pin state or value changes
      def update_simulation
        return if force || !simulation_index || !tester.timeset || !simulator_needs_update?
        case state
          when :drive
            @simulator_state = :drive
            @simulator_value = value
            simulator.put("2^#{simulation_index}^#{value}")
          when :compare
            if tester.read_reg_open?
              tester.read_reg_cycles[tester.cycle_count + 1] ||= {}
              tester.read_reg_cycles[tester.cycle_count + 1][self] = state_meta
              tester.read_reg_meta_supplied = true if state_meta[:position]
            end
            @simulator_state = :compare
            @simulator_value = value
            simulator.put("4^#{simulation_index}^#{value}")
          when :dont_care
            @simulator_state = :dont_care
            simulator.put("5^#{simulation_index}")
          when :capture
            @simulator_state = :capture
            simulator.put("e^#{simulation_index}")
          when :drive_very_high, :drive_mem, :expect_mem, :compare_midband
            fail "Simulation of pin state #{state} is not implemented yet!"
          else
            fail "Simulation of pin state #{state} is not implemented yet!"
        end
      end
    end
  end
end
