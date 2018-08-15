require 'origen_testers/api'
module OrigenTesters
  module API
    # Returns true if the tester is an instance of OrigenSim::Tester,
    # otherwise returns false
    def sim?
      is_a?(OrigenSim::Tester)
    end
    alias_method :simulator?, :sim?

    def sim_delay(id, options = {}, &block)
      id = "delay_#{id}".to_sym  # Just to make sure it is unique from the sim_capture IDs
      if @sim_capture || @sim_delay
        fail 'Nesting of sim_capture and/or sim_delay blocks is not yet supported!'
      end
      Origen::OrgFile.open(id) do |org_file|
        orig_id = id
        @org_file = org_file
        if update_capture?
          @sim_delay = true
          # This enables errors to be captured in a separate variable so that they don't affect
          # the overall simulation result
          start_cycle = cycle_count
          delay = 0
          simulator.match_loop do
            e = -1
            until e == simulator.match_errors
              delay = cycle_count - start_cycle
              e = simulator.match_errors
              pre_block_cycle = cycle_count
              block.call
              # Make sure time is advancing, the block does not necessarily have to advance time
              1.cycle if pre_block_cycle == cycle_count
            end
          end
          Origen.log.debug "sim_delay #{orig_id} resolved after #{delay} cycles"
          # We now know how long it took before the block could pass, now record that information
          # to the org file for next time
          org_file.record('tester', 'cycle')
          org_file.file  # Need to call this since we are bypassing the regular capture API here
          Origen::OrgFile.cycle(delay)
        else
          org_file.read_line do |operations, cycles|
            cycles.cycles
          end
        end
      end
      # Finally execute the block after waiting
      block.call
    end

    def sim_capture(id, *pins)
      if @sim_capture || @sim_delay
        fail 'Nesting of sim_capture and/or sim_delay blocks is not yet supported!'
      end
      options = pins.last.is_a?(Hash) ? pins.pop : {}
      pins = pins.map { |p| p.is_a?(String) || p.is_a?(Symbol) ? dut.pin(p) : p }
      pins.each(&:save)
      @sim_capture = pins.map { |p| [p, "origen.dut.#{p.rtl_name}"] }
      Origen::OrgFile.open(id) do |org_file|
        @org_file = org_file
        if update_capture?
          @sim_capture.each { |pin, net| pin.record_to_org_file(only: :assert) }
        end
        yield
      end
      pins.each(&:restore)
      @sim_capture = nil
    end

    alias_method :_origen_testers_cycle, :cycle
    def cycle(options = {})
      if @sim_capture
        # Need to un-roll all repeats to be sure we observe the true data, can't
        # really assume that it will be constant for all cycles covered by the repeat
        cycles = options.delete(:repeat) || 1
        cycles.times do
          if update_capture?
            _origen_testers_cycle(options)
            @sim_capture.each do |pin, net|
              pin.assert(simulator.peek(net))
              # Remove the assertion since it is for the previous cycle in terms of the current simulation,
              # this won't be captured to the org file
              pin.dont_care
            end
            Origen::OrgFile.cycle
          else
            unless @org_file.exist?
              fail "The simulation capture \"#{id}\" has not been made yet, re-run this pattern with a simulation target first!"
            end
            apply_captured_data
            _origen_testers_cycle(options)
          end
        end
      else
        _origen_testers_cycle(options)
      end
    end

    def apply_captured_data
      if @apply_captured_data_cycles && @apply_captured_data_cycles > 1
        @apply_captured_data_cycles -= 1
      else
        @org_file.read_line do |operations, cycles|
          @apply_captured_data_cycles = cycles
          operations.each do |object, operation, *args|
            object.send(operation, *args)
          end
        end
      end
    end

    def update_capture?
      sim? && (!@org_file.exist? || Origen.app!.update_sim_captures)
    end
  end
end
