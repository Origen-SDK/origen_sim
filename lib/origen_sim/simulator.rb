require 'socket'
module OrigenSim
  # Responsible for managing and communicating with the simulator
  # process, a single instance of this class is instantiated as
  # OrigenSim.simulator
  class Simulator
    include Origen::PersistentCallbacks

    attr_reader :socket, :failed

    def start
      server = UNIXServer.new(socket_id)

      rake_pid = spawn("rake origen_sim:run[#{socket_number}]")
      Process.detach(rake_pid)

      timeout_connection(5) do
        @socket = server.accept
        @connection_established = true
        if @connection_timed_out
          @failed_to_start = true
          Origen.log.error 'Simulator failed to respond'
          @failed = true
          exit
        end
      end
      data = get
      unless data.strip == 'READY!'
        @failed_to_start = true
        fail "The simulator didn't start properly!"
      end
      @enabled = true
    end

    # Returns the pid of the simulator process
    def pid
      f = "#{Origen.root}/tmp/origen_sim/pids/#{socket_number}"
      File.readlines(f).first.strip.to_i
    end

    # Send the given message string to the simulator
    def put(msg)
      socket.write(msg + "\n") if socket
    end

    # Get a message from the simulator, will block until one
    # is received
    def get
      socket.readline
    end

    # This will be called at the end of every pattern, make
    # sure the simulator is not running behind before potentially
    # moving onto another pattern
    def pattern_generated(path)
      sync_up if simulation_tester?
    end

    # Called before every pattern is generated, but we only use it the
    # first time it is called to kick off the simulator process if the
    # current tester is an OrigenSim::Tester
    def before_pattern(name)
      if simulation_tester?
        unless @enabled
          # When running pattern back-to-back, only want to launch the simulator the
          # first time
          unless socket
            start
          end
        end
        # Set the current pattern name in the simulation
        put("a^#{name.sub(/\..*/, '')}")
      end
    end

    # Applies the current state of all pins to the simulation
    def put_all_pin_states
      dut.pins.each { |name, pin| pin.update_simulation }
    end

    # This will be called automatically whenever tester.set_timeset
    # has been called
    def on_timeset_changed
      # Important that this is done first, since it is used to clear the pin
      # and wave definitions in the bridge
      set_period(dut.current_timeset_period)
      # Clear pins and waves
      define_pins
      define_waves
      # Apply the pin reset values / re-apply the existing states
      put_all_pin_states
    end

    # Tells the simulator about the pins in the current device so that it can
    # set up internal handles to efficiently access them
    def define_pins
      dut.pins.each_with_index do |(name, pin), i|
        pin.simulation_index = i
        put("0^#{pin.id}^#{i}^#{pin.drive_wave.index}^#{pin.compare_wave.index}")
      end
    end

    def wave_to_str(wave)
      wave.evaluated_events.map do |time, data|
        if data == :x
          data = 'X'
        elsif data == :data
          data = wave.drive? ? 'D' : 'C'
        end
        if data == 'C'
          "#{time}_#{data}_#{time + 1}_X"
        else
          "#{time}_#{data}"
        end
      end.join('_')
    end

    def define_waves
      dut.timeset.drive_waves.each_with_index do |wave, i|
        put("6^#{i}^0^#{wave_to_str(wave)}")
      end
      dut.timeset.compare_waves.each_with_index do |wave, i|
        put("6^#{i}^1^#{wave_to_str(wave)}")
      end
    end

    def end_simulation
      put('8^')
    end

    def set_period(period_in_ns)
      put("1^#{period_in_ns}")
    end

    def cycle(number_of_cycles)
      put("3^#{number_of_cycles}")
    end

    # Blocks the Origen process until the simulator indicates that it has
    # processed all operations up to this point
    def sync_up
      put('7^')
      data = get
      unless data.strip == 'OK!'
        fail 'Origen and the simulator are out of sync!'
      end
    end

    # Returns the current simulation error count
    def error_count
      peek('origen_tb.debug.errors')
    end

    # Returns the current value of the given net, or nil if the given path does not
    # resolve to a valid node
    def peek(net)
      sync_up
      put("9^#{clean(net)}")
      m = get.strip
      if m == 'FAIL'
        nil
      else
        m.to_i
      end
    end

    def interactive_shutdown
      @interactive_mode = true
    end

    # Stop the simulator
    def stop
      end_simulation
      @socket.close if @socket
      File.unlink(socket_id) if File.exist?(socket_id)
    end

    def on_origen_shutdown
      if @enabled
        unless @interactive_mode
          Origen.log.debug 'Shutting down simulator...'
          unless @failed_to_start
            c = error_count
            if c > 0
              @failed = true
              Origen.log.error "The simulation failed with #{c} errors!"
            end
          end
        end
        stop
        unless @interactive_mode
          if failed
            Origen.app.stats.report_fail
          else
            Origen.app.stats.report_pass
          end
        end
      end
    end

    def socket_id
      @socket_id ||= "/tmp/#{socket_number}.sock"
    end

    def socket_number
      @socket_number ||= (Process.pid.to_s + Time.now.to_f.to_s).sub('.', '')
    end

    def simulation_tester?
      (tester && tester.is_a?(OrigenSim::Tester))
    end

    def timeout_connection(wait_in_s)
      @connection_timed_out = false
      t = Thread.new do
        sleep wait_in_s
        # If the Verilog process has not established a connection yet, then make one to
        # release our process and then exit
        unless @connection_established
          @connection_timed_out = true
          UNIXSocket.new(socket_id).puts(message)
        end
      end
      yield
    end

    private

    def clean(net)
      if net =~ /^dut\./
        "origen_tb.#{net}"
      else
        net
      end
    end
  end
end
