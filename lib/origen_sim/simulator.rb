require 'socket'
require 'io/wait'
module OrigenSim
  # Responsible for managing and communicating with the simulator
  # process, a single instance of this class is instantiated as
  # OrigenSim.simulator
  class Simulator
    include Origen::PersistentCallbacks

    VENDORS = [:icarus, :cadence, :synopsys, :generic]

    attr_reader :socket, :failed, :configuration, :stderr, :stdout, :heartbeat
    alias_method :config, :configuration
    # Returns the PID of the simulator process
    attr_reader :pid

    def initialize
      @socket_ids = {}
    end

    # When set to true the simulator will log all messages it receives, note that
    # this must be run in conjunction with -d supplied to the Origen command to actually
    # see the messages
    def log_messages=(val)
      if val
        put('d^1')
      else
        put('d^0')
      end
    end

    def testbench_top
      config[:testbench_top] || 'origen'
    end

    def rtl_top
      config[:rtl_top] || 'dut'
    end

    def pre_run_start_block
      config[:pre_run_start_block]
    end

    def post_run_start_block
      config[:post_run_start_block]
    end
    
    def generic_run_cmd
      config[:generic_run_cmd]
    end
    
    def post_process_run_cmd
      config[:post_process_run_cmd]
    end

    def fetch_simulation_objects(options = {})
      sid = options[:id] || id
      ldir = "#{Origen.root}/simulation/#{sid}"
      tmp_dir = "#{Origen.root}/tmp/origen_sim/tmp"
      if config[:rc_dir_url]
        unless config[:rc_version]
          puts "You must supply an :rc_version option when using :rc_dir_url (you can set this to something like 'Trunk' or 'master' if you want)"
          exit 1
        end
        if !File.exist?(compiled_dir) ||
           (File.exist?(compiled_dir) && Dir.entries(compiled_dir).size <= 2) ||
           (Origen.app.session.origen_sim[sid] != config[:rc_version]) ||
           options[:force]
          Origen.log.info "Fetching the simulation object for #{sid}..."
          Origen.app.session.origen_sim[sid] = nil # Clear this up front, if the checkout fails we won't know what we have
          FileUtils.rm_rf(tmp_dir) if File.exist?(tmp_dir)
          FileUtils.mkdir_p(tmp_dir)
          FileUtils.mkdir_p("#{Origen.root}/simulation")
          rc = Origen::RevisionControl.new remote: config[:rc_dir_url], local: tmp_dir
          rc.checkout "#{sid}.tar.gz", force: true, version: config[:rc_version]
          FileUtils.mv "#{tmp_dir}/#{sid}.tar.gz", "#{Origen.root}/simulation"
          FileUtils.rm_rf(ldir) if File.exist?(ldir)
          Dir.chdir "#{Origen.root}/simulation/" do
            system "tar -xvf #{sid}.tar.gz"
          end
          Origen.app.session.origen_sim[sid] = config[:rc_version]
        end
      else
        if !File.exist?(compiled_dir) ||
           (File.exist?(compiled_dir) && Dir.entries(compiled_dir).size <= 2)
          puts "There is no previously compiled simulation object in: #{compiled_dir}"
          exit 1
        end
      end
    ensure
      FileUtils.rm_f "#{ldir}.tar.gz" if File.exist?("#{ldir}.tar.gz")
      FileUtils.rm_rf tmp_dir if File.exist?(tmp_dir)
    end

    def commit_simulation_objects(options = {})
      sid = options[:id] || id
      ldir = "#{Origen.root}/simulation/#{sid}"
      tmp_dir = "#{Origen.root}/tmp/origen_sim/tmp"
      unless File.exist?(ldir)
        fail "The simulation directory to check in does not exist: #{ldir}"
      end
      Dir.chdir "#{Origen.root}/simulation/" do
        system "tar -cvzf #{sid}.tar.gz #{sid}"
      end

      FileUtils.rm_rf(tmp_dir) if File.exist?(tmp_dir)
      FileUtils.mkdir_p(tmp_dir)
      FileUtils.cp "#{ldir}.tar.gz", tmp_dir

      rc = Origen::RevisionControl.new remote: config[:rc_dir_url], local: tmp_dir
      rc.checkin "#{sid}.tar.gz", unmanaged: true, force: true, comment: 'Checked in via sim:rc command'
    ensure
      FileUtils.rm_f "#{ldir}.tar.gz" if File.exist?("#{ldir}.tar.gz")
      FileUtils.rm_rf tmp_dir if File.exist?(tmp_dir)
    end

    def configure(options, &block)
      fail 'A vendor must be supplied, e.g. OrigenSim::Tester.new(vendor: :icarus)' unless options[:vendor]
      unless VENDORS.include?(options[:vendor])
        fail "Unknown vendor #{options[:vendor]}, valid values are: #{VENDORS.map { |v| ':' + v.to_s }.join(', ')}"
      end
      @configuration = options
      @tmp_dir = nil
    end

    # The ID assigned to the current simulation target, falls back to to the
    # Origen target name if an :id option is not supplied when instantiating
    # the tester
    def id
      config[:id] || Origen.target.name
    end

    def tmp_dir
      @tmp_dir ||= begin
        d = "#{Origen.root}/tmp/origen_sim/#{id}/#{config[:vendor]}"
        FileUtils.mkdir_p(d)
        d
      end
    end

    # Returns the directory where the compiled simulation object lives, this should
    # be checked into your Origen app's repository
    def compiled_dir
      @compiled_dir ||= begin
        d = "#{Origen.root}/simulation/#{id}/#{config[:vendor]}"
        FileUtils.mkdir_p(d)
        d
      end
    end

    def wave_dir
      @wave_dir ||= begin
        d = "#{Origen.root}/waves/#{id}"
        FileUtils.mkdir_p(d)
        d
      end
    end

    def wave_config_dir
      @wave_config_dir ||= begin
        d = "#{Origen.root}/config/waves/#{id}"
        FileUtils.mkdir_p(d)
        d
      end
    end

    def wave_config_file
      @wave_config_file ||= begin
        f = "#{wave_config_dir}/#{User.current.id}.#{wave_config_ext}"
        unless File.exist?(f)
          # Take a default wave if one has been set up
          d = "#{wave_config_dir}/default.#{wave_config_ext}"
          if File.exist?(d)
            FileUtils.cp(d, f)
          else
            # Otherwise seed it with the latest existing setup by someone else
            d = Dir.glob("#{wave_config_dir}/*.#{wave_config_ext}").max { |a, b| File.ctime(a) <=> File.ctime(b) }
            if d
              FileUtils.cp(d, f)
            else
              # We tried our best, start from scratch
              d = "#{Origen.root!}/templates/empty.#{wave_config_ext}"
              FileUtils.cp(d, f) if File.exist?(d)
            end
          end
        end
        f
      end
    end

    def wave_config_ext
      case config[:vendor]
      when :icarus
        'gtkw'
      when :cadence
        'svcf'
      when :synopsys
        'tcl'
      end
    end

    def run_cmd
      case config[:vendor]
      when :icarus
        cmd = configuration[:vvp] || 'vvp'
        cmd += " -M#{compiled_dir} -morigen #{compiled_dir}/origen.vvp +socket+#{socket_id}"

      when :cadence
        input_file = "#{tmp_dir}/#{id}.tcl"
        if !File.exist?(input_file) || config_changed?
          Origen.app.runner.launch action:            :compile,
                                   files:             "#{Origen.root!}/templates/probe.tcl.erb",
                                   output:            tmp_dir,
                                   check_for_changes: false,
                                   quiet:             true,
                                   options:           { dir: wave_dir, force: config[:force], setup: config[:setup], depth: :all },
                                   output_file_name:  "#{id}.tcl"
        end
        input_file_fast = "#{tmp_dir}/#{id}_fast.tcl"
        if !File.exist?(input_file_fast) || config_changed?
          fast_probe_depth = config[:fast_probe_depth] || 1
          Origen.app.runner.launch action:            :compile,
                                   files:             "#{Origen.root!}/templates/probe.tcl.erb",
                                   output:            tmp_dir,
                                   check_for_changes: false,
                                   quiet:             true,
                                   options:           { dir: wave_dir, force: config[:force], setup: config[:setup], depth: fast_probe_depth },
                                   output_file_name:  "#{id}_fast.tcl"
        end
        save_config_signature
        wave_dir  # Ensure this exists since it won't be referenced above if the input file is already generated

        cmd = configuration[:irun] || 'irun'
        cmd += " -r origen -snapshot origen +socket+#{socket_id}"
        cmd += $use_fast_probe_depth ? " -input #{input_file_fast}" : " -input #{input_file}"
        cmd += " -nclibdirpath #{compiled_dir}"

      when :synopsys
        cmd = "#{compiled_dir}/simv +socket+#{socket_id} -vpd_file origen.vpd"

      when :generic
        # Generic tester requires that a generic_run_command option/block be provided.
        # This should either be a string, an array (which will be joined here), or a block that needs to return either
        # a string or array. In the event of a block, the block will be given the simulator.
        if generic_run_cmd
          cmd = generic_run_cmd
          if cmd.is_a?(Proc)
            cmd = cmd.call(self)
          end
          
          if cmd.is_a?(Array)
            # We'll join this together with the '; ' string. This means that each array element will be run
            # sequentially.
            cmd = cmd.join(' && ')
          elsif !cmd.is_a?(String)
            # If its Proc, it was already run, and if its a Array if would have gone into the other case.
            # So, this is either another proc, not an array and not a string, so not sure what to do with this.
            # Complain about the cmd.
            fail "OrigenSim :generic_run_cmd is of class #{generic_run_cmd.class}. It must be either an Array, String, or a Proc that returns an Array or String."
          end
        else
          fail 'OrigenSim Generic Toolchain/Vendor requires a :generic_run_cmd option/block to be provided. No options/block provided!'
        end

      else
        fail "Run cmd not defined yet for simulator #{config[:vendor]}"

      end
      
      # Allow the user to post-process the command. This should be a block which will be given two parameters:
      # 1. the command, and 2. the simulation object (self).
      # In the event of a generic tester, this *could* replace the launch command, but that's not the real intention,
      # since a simulator could be made that inherits from a generic simulator setup and still post process the command.
      cmd = post_process_run_cmd.call(cmd, self) if post_process_run_cmd
      fail "OrigenSim: :post_process_run_cmd returned object of class #{cmd.class}. Must return a String." unless cmd.is_a?(String)
      
      cmd
    end

    def view_wave_command
      cmd = nil
      case config[:vendor]
      when :icarus
        edir = Pathname.new(wave_config_dir).relative_path_from(Pathname.pwd)
        cmd = "cd #{edir} && "
        cmd += configuration[:gtkwave] || 'gtkwave'
        dir = Pathname.new(wave_dir).relative_path_from(edir.expand_path)
        cmd += " #{dir}/origen.vcd "
        f = Pathname.new(wave_config_file).relative_path_from(edir.expand_path)
        cmd += " --save #{f} &"

      when :cadence
        edir = Pathname.new(wave_config_dir).relative_path_from(Pathname.pwd)
        cmd = "cd #{edir} && "
        cmd += configuration[:simvision] || 'simvision'
        dir = Pathname.new(wave_dir).relative_path_from(edir.expand_path)
        cmd += " #{dir}/#{id}.dsn #{dir}/#{id}.trn"
        f = Pathname.new(wave_config_file).relative_path_from(edir.expand_path)
        cmd += " -input #{f} &"

      when :synopsys
        edir = Pathname.new(wave_config_dir).relative_path_from(Pathname.pwd)
        cmd = "cd #{edir} && "
        cmd += configuration[:dve] || 'dve'
        dir = Pathname.new(wave_dir).relative_path_from(edir.expand_path)
        cmd += " -vpd #{dir}/origen.vpd"
        f = Pathname.new(wave_config_file).relative_path_from(edir.expand_path)
        cmd += " -session #{f}"
        cmd += ' &'

      when :generic
        # Since this could be anything, the simulator will need to set this up. But, once it is, we can print it here.
        if config[:view_waveform_cmd]
          cmd = config[:view_waveform_cmd]
        else
          Origen.log.warn 'OrigenSim cannot provide a view-waveform command for a :generic vendor.'
          Origen.log.warn 'Please supply a view-waveform command though the :view_waveform_cmd option during the OrigenSim::Generic instantiation.'
        end

      else
        # Print a warning stating an unknown vendor was reached here.
        # This shouldn't happen, but just in case.
        Origen.log.warn "OrigenSim does not know the command to view waveforms for vendor :#{config[:vendor]}!"

      end
      cmd
    end

    def run_dir
      case config[:vendor]
      when :icarus, :synopsys
        wave_dir
      else
        tmp_dir
      end
    end

    # Starts up the simulator process
    def start
      fetch_simulation_objects

      # Socket used for Origen -> Verilog commands
      server = UNIXServer.new(socket_id)
      # Socket used to capture stdout from the simulator
      stdout_socket_id = socket_id(:stdout)
      # Socket used to capture stderr from the simulator
      stderr_socket_id = socket_id(:stderr)
      # Socket used to provide a heartbeat to let the Ruby process in charge of the simulator
      # know that the mast Origen process is still alive. If the Origen process crashes and leaves
      # the simulator running, the child process will automatically reap it after a couple of missed
      # heartbeats
      heartbeat_socket_id = socket_id(:heartbeat)
      server_stdout = UNIXServer.new(stdout_socket_id)
      server_stderr = UNIXServer.new(stderr_socket_id)
      server_heartbeat = UNIXServer.new(heartbeat_socket_id)
      cmd = run_cmd + ' & echo \$!'

      # If the user supplied additional setup to be run, prior to the run call occuring, do this now.
      if pre_run_start_block
        Origen.log.info 'Calling User-Specified pre_run_start Block...'
        pre_run_start_block.call(self) if pre_run_start_block
        Origen.log.info 'Setup Block Finished!'
      end

      launch_simulator = %(
        require 'open3'
        require 'socket'
        require 'io/wait'
        require 'origen'

        pid = nil

        stdout_socket = UNIXSocket.new('#{stdout_socket_id}')
        stderr_socket = UNIXSocket.new('#{stderr_socket_id}')
        heartbeat = UNIXSocket.new('#{heartbeat_socket_id}')

        begin

          Dir.chdir '#{run_dir}' do
            Open3.popen3('#{cmd}') do |stdin, stdout, stderr, thread|
              pid = stdout.gets.strip.to_i
              heartbeat.puts(pid.to_s)

              # Listen for a heartbeat from the main Origen process every 5 seconds, kill the
              # simulator after two missed heartbeats
              Thread.new do
                missed_heartbeats = 0
                loop do
                  sleep 5
                  if heartbeat.ready?
                    while heartbeat.ready? do
                      heartbeat.gets
                    end
                    missed_heartbeats = 0
                  else
                    missed_heartbeats += 1
                  end
                  if missed_heartbeats > 1
                    Process.kill('KILL', pid)
                    exit!(1)
                  end
                end
              end

              threads = []
              threads << Thread.new do
                until (line = stdout.gets).nil?
                  stdout_socket.puts line
                end
              end
              threads << Thread.new do
                until (line = stderr.gets).nil?
                  stderr_socket.puts line
                end
              end
              threads.each(&:join)
            end
          end

        ensure
          # Make sure this process never finishes and leaves the simulator running
          begin
            # If the process already finished, then we will see an Errno exception.
            # It does not harm anything, but looks ugly, so catch it here and ignore.
            Process.kill('KILL', pid) if pid
            0
          rescue Errno::ESRCH => e
            0
          end
        end
      )

      simulator_parent_process = spawn("ruby -e \"#{launch_simulator}\"")
      Process.detach(simulator_parent_process)

      # At this point, the simulator is trying to run, i.e., 'run has started'.
      # If we have a block to run before we wait for the simulator, run that, then wait on it.
      # If the user supplied additional setup to be run, do that now.
      if post_run_start_block
        Origen.log.info 'Calling User-Specified post_run_start Block...'
        post_run_start_block.call(self) if post_run_start_block
        Origen.log.info 'Setup Block Finished!'
      end

      timeout_connection(config[:startup_timeout] || 60) do
        @heartbeat = server_heartbeat.accept
        @pid = heartbeat.gets.chomp.to_i

        # Send a heartbeat to the child process running the simulator every 5 seconds
        Thread.new do
          loop do
            heartbeat.write("OK\n")
            sleep 5
          end
        end

        @stdout = server_stdout.accept
        @stderr = server_stderr.accept
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
      # Tick the simulation on, this seems to be required since any VPI puts operations before
      # the simulation has started are not applied.
      # Note that this is not setting a tester timeset, so the application will still have to
      # do that before generating any vectors.
      set_period(100)
      cycle(1)
      Origen.listeners_for(:simulation_startup).each(&:simulation_startup)
    end

    # Returns true if the simulator process is running
    def running?
      return false unless pid
      begin
        Process.getpgid(pid)
        true
      rescue Errno::ESRCH
        false
      end
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
      @simulation_completed_cleanly = true
    end

    # Called before every pattern is generated, but we only use it the
    # first time it is called to kick off the simulator process if the
    # current tester is an OrigenSim::Tester
    def before_pattern(name)
      @simulation_completed_cleanly = false
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
        @pattern_count ||= 0
        if @pattern_count > 0
          c = error_count
          if c > 0
            Origen.log.error "The simulation currently has #{c} error(s)!"
          else
            Origen.log.success 'There are no simulation errors yet!'
          end
        end
        @pattern_count += 1
      end
    end

    def write_comment(comment)
      # Not sure what the limiting factor here is, the comment memory in the test bench should
      # be able to handle 1024 / 8 length strings, but any bigger than this hangs the simulation
      comment = comment[0..96]
      put("c^#{comment}")
    end

    # Applies the current state of all pins to the simulation
    def put_all_pin_states
      dut.rtl_pins.each do |name, pin|
        pin.reset_simulator_state
        pin.update_simulation
      end
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
      dut.rtl_pins.each_with_index do |(name, pin), i|
        pin.simulation_index = i
        put("0^#{pin.rtl_name}^#{i}^#{pin.drive_wave.index}^#{pin.compare_wave.index}")
      end
      dut.rtl_pins.each do |name, pin|
        pin.apply_force
      end
    end

    def wave_to_str(wave)
      wave.evaluated_events.map do |time, data|
        time = time * time_conversion_factor * (config[:time_factor] || 1)
        if data == :x
          data = 'X'
        elsif data == :data
          data = wave.drive? ? 'D' : 'C'
        end
        if data == 'C'
          "#{time}_#{data}_#{time + (time_conversion_factor * (config[:time_factor] || 1))}_X"
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
      period_in_ps = period_in_ns * time_conversion_factor * (config[:time_factor] || 1)
      put("1^#{period_in_ps}")
    end

    def cycle(number_of_cycles)
      put("3^#{number_of_cycles}")
      read_sim_output
    end

    # Blocks the Origen process until the simulator indicates that it has
    # processed all operations up to this point
    def sync_up
      put('7^')
      data = get
      unless data.strip == 'OK!'
        fail 'Origen and the simulator are out of sync!'
      end
      read_sim_output
    end

    def read_sim_output
      while stdout.ready?
        line = stdout.gets.chomp
        if OrigenSim.error_strings.any? { |s| line =~ /#{s}/ } &&
           !OrigenSim.error_string_exceptions.any? { |s| line =~ /#{s}/ }
          @simulator_logged_errors = true
          Origen.log.error line
        else
          if OrigenSim.verbose? ||
             OrigenSim.log_strings.any? { |s| line =~ /#{s}/ }
            Origen.log.info line
          else
            Origen.log.debug line
          end
        end
      end
      while stderr.ready?
        line = stderr.gets.chomp
        if OrigenSim.fail_on_stderr && !OrigenSim.stderr_string_exceptions.any? { |s| line =~ /#{s}/ }
          # We're failing on stderr, so print its results and log as errors if its not an exception.
          @stderr_logged_errors = true
          Origen.log.error line
        elsif OrigenSim.verbose?
          # We're not failing on stderr, or the string in stderr is an exception.
          # Print the string as regular output if verbose is set, otherwise just ignore.
          Origen.log.info line
        end
      end
    end

    # Returns the current simulation error count
    def error_count
      peek("#{testbench_top}.debug.errors").to_i
    end

    # Returns the current value of the given net, or nil if the given path does not
    # resolve to a valid node
    #
    # The value is returned as an instance of Origen::Value
    def peek(net)
      # The Verilog spec does not specify that underlying VPI put method should
      # handle a part select, so some simulators do not handle it. Therefore we
      # deal with it here to ensure cross simulator compatibility.

      # http://rubular.com/r/eTVGzrYmXQ
      if net =~ /(.*)\[(\d+):?(\.\.)?(\d*)\]$/
        net = Regexp.last_match(1)
        msb = Regexp.last_match(2).to_i
        lsb = Regexp.last_match(4)
        lsb = lsb.empty? ? nil : lsb.to_i
      end

      sync_up
      put("9^#{clean(net)}")
      m = get.strip

      if m == 'FAIL'
        return nil
      else
        if msb
          # Setting a range of bits
          if lsb
            Origen::Value.new('b' + m[(m.size - 1 - msb)..(m.size - 1 - lsb)])
          else
            Origen::Value.new('b' + m[m.size - 1 - msb])
          end
        else
          Origen::Value.new('b' + m)
        end
      end
    end

    # Forces the given value to the given net.
    # Note that no error checking is done and no error will be communicated if an illegal
    # net is supplied. The user should follow up with a peek if they want to verify that
    # the poke was applied.
    def poke(net, value)
      # The Verilog spec does not specify that underlying VPI put method should
      # handle a part select, so some simulators do not handle it. Therefore we
      # deal with it here to ensure cross simulator compatibility.

      # http://rubular.com/r/eTVGzrYmXQ
      if !config[:vendor] == :synopsys && net =~ /(.*)\[(\d+):?(\.\.)?(\d*)\]$/
        path = Regexp.last_match(1)
        msb = Regexp.last_match(2).to_i
        lsb = Regexp.last_match(4)
        lsb = lsb.empty? ? nil : lsb.to_i

        v = peek(path)
        return nil unless v
        # Setting a range of bits
        if lsb
          upper = v >> (msb + 1)
          # Make sure value does not overflow
          value = value[(msb - lsb)..0]
          if lsb == 0
            value = (upper << (msb + 1)) | value
          else
            lower = v[(lsb - 1)..0]
            value = (upper << (msb + 1)) |
                    (value << lsb) | lower
          end

        # Setting a single bit
        else
          if msb == 0
            upper = v >> 1
            value = (upper << 1) | value[0]
          else
            lower = v[(msb - 1)..0]
            upper = v >> (msb + 1)
            value = (upper << (msb + 1)) |
                    (value[0] << msb) | lower
          end
        end
        net = path
      end

      sync_up
      put("b^#{clean(net)}^#{value}")
    end

    def interactive_shutdown
      @interactive_mode = true
    end

    # Stop the simulator
    def stop
      Origen.listeners_for(:simulation_shutdown).each(&:simulation_shutdown)
      ended = Time.now
      end_simulation
      # Give the simulator time to shut down
      sleep 0.1 while running?
      socket.close if socket
      stderr.close if stderr
      stdout.close if stdout
      heartbeat.close if heartbeat
      File.unlink(socket_id) if File.exist?(socket_id)
      File.unlink(socket_id(:stderr)) if File.exist?(socket_id(:stderr))
      File.unlink(socket_id(:stdout)) if File.exist?(socket_id(:stdout))
      File.unlink(socket_id(:heartbeat)) if File.exist?(socket_id(:heartbeat))
    end

    def on_origen_shutdown
      if @enabled
        unless @interactive_mode
          Origen.log.debug 'Shutting down simulator...'
          unless @failed_to_start
            c = error_count
            if c > 0 || @simulator_logged_errors || @stderr_logged_errors
              @failed = true
              Origen.log.error "The simulation failed with #{c} errors!" if c > 0
              Origen.log.error 'The simulation log reported errors!' if @simulator_logged_errors
              Origen.log.error 'The simulation stderr reported errors!' if @stderr_logged_errors
            elsif !@simulation_completed_cleanly
              @failed = true
              Origen.log.error 'The simulation exited early!'
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
        if view_wave_command
          puts
          puts 'To view the simulation run the following command:'
          puts
          puts "  #{view_wave_command}"
          puts
        end
      end
    end

    def socket_id(type = nil)
      @socket_ids[type] ||= "/tmp/#{socket_number}#{type}.sock"
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
          UNIXSocket.new(socket_id).puts("Time out\n")
        end
      end
      yield
    end

    def sync
      put('f')
      @sync_active = true
      yield
      put('g')
      @sync_active = false
    end

    def sync_active?
      @sync_active
    end

    # Returns true if the config has been changed since the last time we called save_config_signature
    def config_changed?
      Origen.app.session.origen_sim["#{id}_config"] != config
    end

    # Locally saves a signature for the current config, this will cause config_changed? to return false
    # until its contents change
    def save_config_signature
      Origen.app.session.origen_sim["#{id}_config"] = config
    end

    # Returns the version of Origen Sim that the current DUT object was compiled with
    def dut_version
      @dut_version ||= begin
        put('i^')
        Origen::VersionString.new(get.strip)
      end
    end

    private

    # Pre 0.8.0 the simulator represented the time in ns instead of ps
    def time_conversion_factor
      @time_conversion_factor ||= dut_version < '0.8.0' ? 1 : 1000
    end

    def clean(net)
      if net =~ /^dut\./
        "origen.#{net}"
      else
        net
      end
    end
  end
end
