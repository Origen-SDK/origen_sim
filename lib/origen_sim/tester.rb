module OrigenSim
  # Responsible for interfacing the simulator with Origen
  class Tester
    include OrigenTesters::VectorBasedTester

    TEST_PROGRAM_GENERATOR = OrigenSim::Generator

    def initialize(options = {})
      simulator.configure(options)
      super()
    end

    def simulator
      OrigenSim.simulator
    end

    def handshake(options = {})
    end

    def capture
      simulator.sync do
        @sync_pins = []
        @sync_cycles = 0
        yield
      end
      @sync_pins.map { |pin| simulator.peek("origen.pins.#{pin.id}.sync_memory[#{@sync_cycles - 1}:0]") }
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
      simulator.cycle(options[:repeat] || 1)
      if @after_next_vector
        @after_next_vector.call(@after_next_vector_args)
        @after_next_vector = nil
      end
    end

    def c1(msg, options = {})
      simulator.write_comment(msg) if @step_comment_on
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
        pins.each do |pin|
          @sync_cycles += 1
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

    def sim_capture(id, *pins)
      options = pins.last.is_a?(Hash) ? pins.pop : {}
      @sim_capture = pins.map { |p| [p, "origen.dut.#{p.rtl_name}"] }
      with_capture_file(id) do
        yield
      end
      @sim_capture = nil
    end

    def cycle(options = {})
      if @sim_capture
        # Need to un-roll all repeats to be sure we observe the true data, can't
        # really assume that it will be constant for all cycles covered by the repeat
        cycles = options.delete(:repeat) || 1
        cycles.times do
          if update_capture?
            super
            l = ''
            @sim_capture.each do |pin, net|
              l += "#{pin.id},#{simulator.peek(net)};"
            end
            capture_file.puts l
          else
            apply_captured_data
            super
          end
        end
      else
        super
      end
    end

    private

    def apply_captured_data
      read_capture_line do |line|
        line.each do |pin_id, data|
          dut.pin(pin_id).assert(data.to_i(2))
        end
      end
    end

    def read_capture_line
      yield @capture_file.readline.strip.split(';').map { |l| l.split(',') }
    end

    def update_capture?
      return @update_capture if defined? @update_capture
      @update_capture = !@capture_present || Origen.app!.update_sim_captures
    end

    def with_capture_file(id)
      filename = "#{capture_dir}/#{id}"
      @capture_present = File.exist?(filename)
      if update_capture?
        File.open(filename, 'w') do |f|
          @capture_file = f
          yield
        end
      else
        File.open(filename, 'r') do |f|
          @capture_file = f
          yield
        end
      end
      @capture_file = nil
    end

    def capture_file
      @capture_file
    end

    def capture_dir
      @capture_dir ||= begin
        d = "#{Origen.root}/pattern/sim_capture/#{Origen.target.name}/"
        FileUtils.mkdir_p(d)
        d
      end
    end

    def after_next_vector(*args, &block)
      @after_next_vector = block
      @after_next_vector_args = args
    end
  end
end
