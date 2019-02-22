module OrigenSim
  # Responsible for interfacing the simulator with Origen
  class Tester
    include OrigenTesters::VectorBasedTester

    TEST_PROGRAM_GENERATOR = OrigenSim::Generator

    def initialize(options = {}, &block)
      # Use Origen's collector to allow options to be set either from the options hash, or from the block
      if block_given?
        opts = Origen::Utility.collector(hash: options, merge_method: :keep_hash, &block).to_hash
      else
        opts = options
      end

      simulator.configure(opts, &block)
      @comment_buffer = []
      @last_comment_size = 0
      super()
    end

    # Returns the current cycle count
    def cycle_count
      @cycle_count || 0
    end

    def simulator
      OrigenSim.simulator
    end

    def dut_version
      simulator.dut_version
    end

    def handshake(options = {})
    end

    def capture
      simulator.sync do
        @sync_pins = []
        @sync_cycles = 0
        yield
      end
      @sync_pins.map do |pin|
        if @sync_cycles.size == 1
          simulator.peek("origen.pins.#{pin.id}.sync_memory[0]")
        else
          simulator.peek("origen.pins.#{pin.id}.sync_memory[#{@sync_cycles - 1}:0]")
        end
      end
    end

    # Start the simulator
    def start
      simulator.start
    end

    # Blocks the Origen process until the simulator indicates that it has
    # processed all operations up to this point
    def sync_up
      simulator.sync_up
    end

    # Flush any buffered simulation output, this should cause live waveviewers to
    # reflect the latest state
    def flush
      simulator.flush
    end

    def set_timeset(name, period_in_ns)
      super
      # Need to remove this once OrigenTesters does it
      dut.timeset = name
      dut.current_timeset_period = period_in_ns

      # Now update the simulator with the new waves
      simulator.on_timeset_changed
    end

    # This method intercepts vector data from Origen, removes white spaces and compresses repeats
    def push_vector(options)
      unless options[:timeset]
        puts 'No timeset defined!'
        puts 'Add one to your top level startup method or target like this:'
        puts '$tester.set_timeset("nvmbist", 40)   # Where 40 is the period in ns'
        exit 1
      end
      flush_comments unless @comment_buffer.empty?
      simulator.cycle(options[:repeat] || 1)
      @cycle_count ||= 0
      @cycle_count += options[:repeat] || 1
      if @after_next_vector
        @after_next_vector.call(@after_next_vector_args)
        @after_next_vector = nil
      end
    end

    def c1(msg, options = {})
      if @step_comment_on
        simulator.log msg
        @comment_buffer << msg
      end
    end

    def ss(msg = nil)
      simulator.log '=' * 70
      super
      simulator.log '=' * 70
    end

    def loop_vectors(name, number_of_loops, options = {})
      number_of_loops.times do
        yield
      end
    end
    alias_method :loop_vector, :loop_vectors

    # Capture the next vector generated
    #
    # This method applies a store request to the next vector to be generated,
    # note that is does not actually generate a new vector.
    #
    # The captured data is added to the captured_data array.
    #
    # This method is intended to be used by pin drivers, see the #capture method for the application
    # level API.
    #
    # @example
    #   tester.store_next_cycle
    #   tester.cycle                # This is the vector that will be captured
    def store_next_cycle(*pins)
      options = pins.last.is_a?(Hash) ? pins.pop : {}
      if pins.empty?
        pins = dut.rtl_pins.values
      else
        pins_orig = pins.dup
        pins_orig.each do |p|
          if p.is_a? Origen::Pins::PinCollection
            pins.concat(p.map(&:id).map { |p| dut.pin(p) })
            pins.delete(p)
          end
        end
      end
      if simulator.sync_active?
        @sync_cycles += 1
        pins.each do |pin|
          @sync_pins << pin unless @sync_pins.include?(pin)
        end
      end
      pins.each(&:capture)
      # A store request is only valid for one cycle, this tells the simulator
      # to stop after the next vector is generated
      after_next_vector do
        pins.each { |pin| simulator.put("h^#{pin.simulation_index}") }
      end
    end

    def match(pin, state, timeout_in_cycles, options = {})
      if dut_version <= '0.12.0'
        OrigenSim.error "Use of match loops requires a DUT model compiled with OrigenSim version > 0.12.0, the current dut was compiled with #{dut_version}"
      end
      expected_val = state == :high ? 1 : 0
      if options[:pin2]
        expected_val2 = options[:state2] == :high ? 1 : 0
      end
      timed_out = true
      10.times do
        (timeout_in_cycles / 10).cycles
        current_val = simulator.peek("dut.#{pin.rtl_name}").to_i
        if options[:pin2]
          current_val2 = simulator.peek("dut.#{options[:pin2].rtl_name}").to_i
          if current_val == expected_val || current_val2 == expected_val2
            timed_out = false
            break
          end
        else
          if current_val == expected_val
            timed_out = false
            break
          end
        end
      end
      # Final assertion to make the pattern fail if the loop timed out
      if timed_out
        pin.restore_state do
          pin.assert!(expected_val)
        end
        if options[:pin2]
          options[:pin2].restore_state do
            options[:pin2].assert!(expected_val2)
          end
        end
      end
    end

    def match_block(timeout_in_cycles, options = {}, &block)
      if dut_version <= '0.12.0'
        OrigenSim.error "Use of match loops requires a DUT model compiled with OrigenSim version > 0.12.0, the current dut was compiled with #{dut_version}"
      end
      match_conditions = Origen::Utility::BlockArgs.new
      fail_conditions = Origen::Utility::BlockArgs.new
      if block.arity > 0
        block.call(match_conditions, fail_conditions)
      else
        match_conditions.add(&block)
      end
      timed_out = true
      simulator.match_loop do
        10.times do
          (timeout_in_cycles / 10).cycles
          # Consider the match resolved if any condition can execute without generating errors
          if match_conditions.any? do |condition|
            e = simulator.match_errors
            condition.call
            e == simulator.match_errors
          end
            timed_out = false
            break
          end
        end
      end
      # Final execution to make the pattern fail if the loop timed out
      if timed_out
        if fail_conditions.instance_variable_get(:@block_args).empty?
          match_conditions.each(&:call)
        else
          fail_conditions.each(&:call)
        end
      end
    end

    def wait(*args)
      super
      flush if Origen.running_interactively? && dut_version > '0.12.1'
    end

    private

    def flush_comments
      # Looping for at least the length of the last comment is require to ensure that all lines
      # from the last comment are either overwritten or cleared
      [@comment_buffer.size, @last_comment_size].max.times do |i|
        simulator.write_comment(i, @comment_buffer[i])
      end
      @last_comment_size = @comment_buffer.size
      @comment_buffer.clear
    end

    def after_next_vector(*args, &block)
      @after_next_vector = block
      @after_next_vector_args = args
    end
  end
end
