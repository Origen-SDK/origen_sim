module OrigenSim
  # Responsible for interfacing the simulator with Origen
  class Tester
    include OrigenTesters::VectorBasedTester

    TEST_PROGRAM_GENERATOR = OrigenSim::Generator

    attr_accessor :out_of_bounds_handler

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
      @execution_time_in_ns = 0
      super()
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
          b = simulator.peek("#{simulator.testbench_top}.pins.#{pin.id}.sync_memory")[0]
          if b.is_a?(Integer)
            b
          else
            Origen.log.warning "The data captured on pin #{pin.id} was undefined (X or Z), the captured value is not correct!"
            0
          end
        else
          val = 0
          mem = simulator.peek("#{simulator.testbench_top}.pins.#{pin.id}.sync_memory")
          @sync_cycles.times do |i|
            b = mem[i]
            if b.is_a?(Integer)
              val |= b << i
            else
              Origen.log.warning "The data captured on cycle #{i} of pin #{pin.id} was undefined (X or Z), the captured value is not correct!"
            end
          end
          val
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
    # reflect the latest state and the console and log files to update
    def flush(*args)
      simulator.flush(*args)
    end

    def set_timeset(name, period_in_ns = nil)
      super

      # Need to remove this once OrigenTesters does it
      # OrigenTesters with decompiler supports this.
      if period_in_ns
        dut.timeset = name
        dut.current_timeset_period = period_in_ns
      end

      # Now update the simulator with the new waves
      simulator.on_timeset_changed
    end

    # This method intercepts vector data from Origen, removes white spaces and compresses repeats
    def push_vector(options)
      if simulator.simulation.max_errors_exceeded
        fail Origen::Generator::AbortError, 'The max error count has been exceeded in the simulation'
      else
        unless options[:timeset]
          puts 'No timeset defined!'
          puts 'Add one to your top level startup method or target like this:'
          puts 'tester.set_timeset("nvmbist", 40)   # Where 40 is the period in ns'
          exit 1
        end
        flush_comments unless @comment_buffer.empty?
        repeat = options[:repeat] || 1
        simulator.cycle(repeat)
        @execution_time_in_ns += repeat * tester.timeset.period_in_ns
        if @after_next_vector
          @after_next_vector.call(@after_next_vector_args)
          @after_next_vector = nil
        end
      end
    end

    def c1(msg, options = {})
      if @step_comment_on
        PatSeq.add_thread(msg) unless options[:no_thread_id]
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
      if simulator.sync_active? && @sync_cycles
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
      matched = false
      start_cycle = cycle_count
      resolution = match_loop_resolution(timeout_in_cycles, options)
      until matched || cycle_count > start_cycle + timeout_in_cycles
        resolution.cycles
        current_val = simulator.peek("dut.#{pin.rtl_name}").to_i
        if options[:pin2]
          current_val2 = simulator.peek("dut.#{options[:pin2].rtl_name}").to_i
          matched = current_val == expected_val || current_val2 == expected_val2
        else
          matched = current_val == expected_val
        end
      end
      # Final assertion to make the pattern fail if the loop timed out
      unless matched
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
      matched = false
      start_cycle = cycle_count
      resolution = match_loop_resolution(timeout_in_cycles, options)
      simulator.match_loop do
        until matched || cycle_count > start_cycle + timeout_in_cycles
          resolution.cycles
          # Consider the match resolved if any condition can execute without generating errors
          matched = match_conditions.any? do |condition|
            e = simulator.match_errors
            condition.call
            e == simulator.match_errors
          end
        end
      end
      # Final execution to make the pattern fail if the loop timed out
      unless matched
        if fail_conditions.instance_variable_get(:@block_args).empty?
          match_conditions.each(&:call)
        else
          fail_conditions.each(&:call)
        end
      end
    end

    # @api private
    def match_loop_resolution(timeout_in_cycles, options)
      if options[:resolution]
        if options[:resolution].is_a?(Hash)
          return time_to_cycles(options[:resolution])
        else
          return options[:resolution]
        end
      else
        # Used to use the supplied timeout / 10, thinking that the supplied number would be
        # roughly how long it would take. However, found that when users didn't know the timeout
        # they would just put in really large numbers, like 1sec, which would mean we would not
        # check until 100ms for an operation that might be done after 100us.
        # So now if the old default comes out less than the new one, then use it, otherwise use
        # the newer more fine-grained default.
        old_default = timeout_in_cycles / 10
        new_default = time_to_cycles(time_in_us: 100)
        return old_default < new_default ? old_default : new_default
      end
    end

    def wait(*args)
      super
      if Origen.running_interactively? ||
         (defined?(Byebug) && Byebug.try(:mode) == :attached)
        flush quiet: true
      end
    end

    def log_file_written(path)
      simulator.simulation.log_files << path if simulator.simulation
    end

    def read_register(reg_or_val, options = {})
      # This could be called multiple times for the same transaction
      if read_reg_open?
        yield
      else
        @read_reg_meta_supplied = false
        @read_reg_open = true
        @read_reg_cycles = {}
        unless @supports_transactions_set
          @supports_transactions = dut_version > '0.15.0'
          @supports_transactions_set = true
        end

        if reg_or_val.respond_to?(:named_bits)
          bit_names = reg_or_val.named_bits.map { |name, bits| name }.uniq
          expected = bit_names.map do |name|
            bits = reg_or_val.bits(name)
            if bits.is_to_be_read?
              [name, bits.status_str(:read)]
            end
          end.compact

          # Save which bits are being read for later, the driver performing the read will
          # clear the register flags
          read_flags = reg_or_val.map(&:is_to_be_read?)
        end

        error_count = simulator.error_count

        simulator.start_read_reg_transaction if @supports_transactions

        yield

        if @supports_transactions
          errors_captured, exceeded_max_errors, errors = *(simulator.stop_read_reg_transaction)
        end

        @read_reg_open = false

        if simulator.error_count > error_count
          if @supports_transactions
            actual_data_available = true
            if exceeded_max_errors
              Origen.log.warning 'The number of errors in this transaction exceeded the capture buffer, the actual data reported here may not be accurate'
            end
            out_of_sync = simulator.simulation.cycle_count != simulator.cycle_count
            if out_of_sync
              Origen.log.warning 'Something has gone wrong and Origen and the simulator do not agree on the current cycle number, it is not possible to resolve the actual data'
              actual_data_available = false
            else
              diffs = []
              errors.each do |error|
                if c = read_reg_cycles[error[:cycle]]
                  if p = c[simulator.pins_by_rtl_name[error[:pin_name]]]
                    if p[:position]
                      diffs << [p[:position], error[:expected], error[:received]]
                    end
                  end
                end
              end
              if diffs.empty?
                if @read_reg_meta_supplied
                  Origen.log.warning 'It looks like the miscompare(s) occurred on pins/cycles that are not associated with register data'
                  non_data_miscompare = true
                else
                  Origen.log.warning 'It looks like your current read register driver does not provide the necessary meta-data to map these errors to an actual register value'
                end
                actual_data_available = false
              end
            end
          else
            Origen.log.warning 'Your DUT needs to be compiled with a newer version of OrigenSim to support reporting of the actual read data from this failed transaction'
            actual_data_available = false
          end

          # If a register object has been supplied...
          if read_flags
            Origen.log.error "Errors occurred reading register #{reg_or_val.path}:"
            if actual_data_available
              actual = nil
              reg_or_val.preserve_flags do
                reg_or_val.each_with_index do |bit, i|
                  bit.read if read_flags[i]
                end

                diffs.each do |position, expected, received|
                  if position < reg_or_val.size
                    if received == -1 || received == -2
                      reg_or_val[position].unknown = true
                    else
                      reg_or_val[position].write(received, force: true)
                    end
                  else
                    # This bit position is beyond the bounds of the register
                    if @out_of_bounds_handler
                      @out_of_bounds_handler.call(position, received, expected, reg_or_val)
                    else
                      Origen.log.error "bit[#{position}] of read operation on #{reg_or_val.path}.#{reg_or_val.name}: expected #{expected} received #{received}"
                    end
                  end
                end

                actual = bit_names.map do |name|
                  bits = reg_or_val.bits(name)
                  if bits.is_to_be_read?
                    [name, bits.status_str(:read)]
                  end
                end.compact

                # Put the data back so the application behaves as it would if generating
                # for a non-simulation tester target
                diffs.each do |position, expected, received|
                  reg_or_val[position].write(expected, force: true) if position < reg_or_val.size
                end
              end
            end

            expected.each do |name, expected|
              msg = "#{reg_or_val.path}.#{name}: expected #{expected}"
              if actual_data_available
                received_ = nil
                actual.each do |name2, received|
                  if name == name2
                    received_ = received
                    msg += " received #{received}"
                  end
                end
                if expected == received_
                  Origen.log.info msg
                else
                  Origen.log.error msg
                end
              else
                # This means that the correct data was read, but errors occurred on other pins/cycles during the transaction
                msg += " received #{expected}" if non_data_miscompare
                Origen.log.error msg
              end
            end
          else
            Origen.log.error 'Errors occurred while reading a register:'
            msg = "expected #{reg_or_val.to_s(16).upcase}"
            if actual_data_available
              actual = reg_or_val
              diffs.each do |position, expected, received|
                if received == -1 || received == -2
                  actual = '?' * reg_or_val.to_s(16).size
                  break
                elsif received == 1
                  actual |= (1 << position)
                else
                  lower = actual[(position - 1)..0]
                  actual = actual >> (position + 1)
                  actual = actual << (position + 1)
                  actual |= lower
                end
              end
              if actual.is_a?(String)
                msg += " received #{actual}"
              else
                msg += " received #{actual.to_s(16).upcase}"
              end
            else
              # This means that the correct data was read, but errors occurred on other pins/cycles during the transaction
              msg += " received #{reg_or_val.to_s(16).upcase}" if non_data_miscompare
            end
            Origen.log.error msg
          end

          Origen.log.error
          caller.each do |line|
            if Pathname.new(line.split(':').first).expand_path.to_s =~ /^#{Origen.root}(?!(\/lbin|\/vendor\/gems)).*$/
              Origen.log.error line
            end
          end
        end
      end
    end

    def read_reg_open?
      @read_reg_open
    end

    def read_reg_cycles
      @read_reg_cycles
    end

    def cycle_count
      simulator.simulation.cycle_count
    end

    def read_reg_meta_supplied=(val)
      @read_reg_meta_supplied = val
    end

    # Shorthand for simulator.poke
    def poke(*args)
      simulator.poke(*args)
    end

    # Shorthand for simulator.peek
    def peek(*args)
      simulator.peek(*args)
    end

    # Shorthand for simulator.peek_real
    def peek_real(*args)
      simulator.peek_real(*args)
    end

    # Shorthand for simulator.force
    def force(*args)
      simulator.force(*args)
    end

    # Shorthand for simulator.release
    def release(*args)
      simulator.release(*args)
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
