require 'origen_testers/api'
module OrigenTesters
  module API
    # Returns true if the tester is an instance of OrigenSim::Tester,
    # otherwise returns false
    def sim?
      is_a?(OrigenSim::Tester)
    end
    alias_method :simulator?, :sim?

    def sim_capture(id, *pins)
      if @sim_capture
        fail 'Nesting of sim_capture blocks is not yet supported!'
      end
      options = pins.last.is_a?(Hash) ? pins.pop : {}
      pins.each(&:save)
      @sim_capture = pins.map { |p| [p, "origen.dut.#{p.rtl_name}"] }
      with_capture_file(id) do
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
            l = ''
            @sim_capture.each do |pin, net|
              l += "#{pin.id},#{simulator.peek(net)};"
            end
            capture_file.puts l
          else
            apply_captured_data
            _origen_testers_cycle(options)
          end
        end
      else
        _origen_testers_cycle(options)
      end
    end

    def with_capture_file(id)
      filename = "#{capture_dir}/#{id}.org"
      @capture_present = File.exist?(filename)
      if update_capture?
        File.open(filename, 'w') do |f|
          @capture_file = f
          yield
        end
      else
        unless File.exist?(filename)
          fail "The simulation capture \"#{id}\" has not been made yet, re-run this pattern with a simulation target first!"
        end
        File.open(filename, 'r') do |f|
          @capture_file = f
          yield
        end
      end
      @capture_file = nil
    end

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
      @update_capture = sim? && (!@capture_present || Origen.app!.update_sim_captures)
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
  end
end
