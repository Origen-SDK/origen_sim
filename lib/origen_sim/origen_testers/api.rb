require 'origen_testers/api'
module OrigenTesters
  module API
    # Returns true if the tester is an instance of OrigenSim::Tester,
    # otherwise returns false
    def sim?
      is_a?(OrigenSim::Tester)
    end
    alias_method :simulator?, :sim?

    def read_register(reg_or_val, options = {})
      yield
    end

    # Set a marker in the OrigenSim testbench
    def marker=(val)
      simulator.marker = val if sim?
    end

    def sim_delay(id, options = {}, &block)
      if sim? && dut_version <= '0.12.0'
        OrigenSim.error "Use of sim_delay requires a DUT model compiled with OrigenSim version > 0.12.0, the current dut was compiled with #{dut_version}"
      end
      orig_id = id
      id = "delay_#{id}".to_sym  # Just to make sure it is unique from the sim_capture IDs
      if @sim_capture || @sim_delay
        fail 'Nesting of sim_capture and/or sim_delay blocks is not yet supported!'
      end
      Origen::OrgFile.open(id, path: (options[:path] || OrigenSim.capture_dir)) do |org_file|
        @org_file = org_file
        if update_capture?
          @sim_delay = true
          # This enables errors to be captured in a separate variable so that they don't affect
          # the overall simulation result
          start_cycle = cycle_count
          delay = 0
          simulator.match_loop do
            if options[:resolution]
              if options[:resolution].is_a?(Hash)
                resolution_in_cycles = time_to_cycles(options[:resolution])
              else
                resolution_in_cycles = options[:resolution]
              end
            end
            timeout_in_cycles = time_to_cycles(options)
            e = -1
            until (e == simulator.match_errors) || (timeout_in_cycles > 0 ? delay > timeout_in_cycles : false)
              delay = cycle_count - start_cycle
              e = simulator.match_errors
              pre_block_cycle = cycle_count
              block.call
              if resolution_in_cycles
                remaining = resolution_in_cycles - (cycle_count - pre_block_cycle)
                remaining.cycles if remaining > 0
              else
                # Make sure time is advancing, the block does not necessarily have to advance time
                1.cycle if pre_block_cycle == cycle_count
              end
            end
          end
          Origen.log.debug "sim_delay #{orig_id} resolved after #{delay} cycles"
          # We now know how long it took before the block could pass, now record that information
          # to the org file for next time
          org_file.record('tester', 'cycle')
          org_file.file  # Need to call this since we are bypassing the regular capture API here
          Origen::OrgFile.cycle(delay)
        else
          unless org_file.exist?
            fail "The simulation delay \"#{orig_id}\" has not been simulated yet, re-run this pattern with a simulation target first!"
          end
          org_file.read_line do |operations, cycles|
            cycles.cycles
          end
        end
      end
      # Finally execute the block after waiting
      if options[:padding]
        time_to_cycles(options[:padding]).cycles
      end
      block.call
      @sim_delay = nil
    end

    def sim_capture(id, *pins)
      if @sim_capture || @sim_delay
        fail 'Nesting of sim_capture and/or sim_delay blocks is not yet supported!'
      end
      @sim_capture_id = id
      options = pins.last.is_a?(Hash) ? pins.pop : {}
      pins = pins.map { |p| p.is_a?(String) || p.is_a?(Symbol) ? dut.pin(p) : p }
      pins.each(&:save)
      @sim_capture = pins.map { |p| [p, "#{simulator.testbench_top || 'origen'}.dut.#{p.rtl_name}"] }
      Origen::OrgFile.open(id, path: OrigenSim.capture_dir) do |org_file|
        @org_file = org_file
        @update_capture = update_capture?
        if @update_capture
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
          if @update_capture
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
              fail "The simulation capture \"#{@sim_capture_id}\" has not been simulated yet, re-run this pattern with a simulation target first!"
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

    def time_to_cycles(options)
      options = {
        cycles:         0,
        time_in_cycles: 0,
        time_in_us:     0,
        time_in_ns:     0,
        time_in_ms:     0,
        time_in_s:      0
      }.merge(options)
      cycles = 0
      cycles += options[:cycles] + options[:time_in_cycles]
      cycles += s_to_cycles(options[:time_in_s])
      cycles += ms_to_cycles(options[:time_in_ms])
      cycles += us_to_cycles(options[:time_in_us])
      cycles += ns_to_cycles(options[:time_in_ns])
      cycles
    end
  end
end
