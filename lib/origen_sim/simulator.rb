require 'origen_sim/simulation'
require 'origen_sim/artifacts'

module OrigenSim
  # Responsible for managing and communicating with the simulator
  # process, a single instance of this class is instantiated as
  # OrigenSim.simulator
  class Simulator
    include Origen::PersistentCallbacks
    include Artifacts

    VENDORS = [:icarus, :cadence, :synopsys, :generic]
    DEFAULT_ARTIFACT_DIR = Pathname("#{Origen.app.root}/simulation/application/artifacts")

    attr_reader :configuration
    alias_method :config, :configuration
    # The instance of OrigenSim::Simulation for the current simulation
    attr_reader :simulation
    # Returns an array containing all instances of OrigenSim::Simulation that were created
    # in the order that they were created
    attr_reader :simulations

    def initialize
      @simulations = []
      @simulation_open = false
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

      # Temporary workaround for bug in componentable, which is making the container a class object, instead of an
      # instance object.
      clear_artifacts

      # Add any artifacts in the given artifact path
      if Dir.exist?(default_artifact_dir)
        default_artifact_dir.children.each { |a| artifact(a.basename.to_s, target: a) }
      end

      # Add any artifacts from the target-specific path (simulation/<target>/artifacts). Files of the same name
      # will override artifacts residing in the default directory.
      if Dir.exist?(target_artifact_dir)
        target_artifact_dir.children.each do |a|
          remove_artifact(a.basename.to_s) if has_artifact?(a.basename.to_s)
          add_artifact(a.basename.to_s, target: a)
        end
      end

      # If a user artifact path was given, add those artifacts as well, overriding any of the default and target artifacts
      if user_artifact_dirs?
        user_artifact_dirs.each do |d|
          if Dir.exist?(d)
            # Add any artifacts from any user-given paths. Files of the same name will override artifacts residing in the default directory.
            d.children.each do |a|
              remove_artifact(a.basename.to_s) if has_artifact?(a.basename.to_s)
              add_artifact(a.basename.to_s, target: a)
            end
          else
            Origen.app.fail! message: "Simulator configuration specified a user artifact dir at #{d} but this directory could not be found!"
          end
        end
      end

      self
    end

    def default_artifact_dir
      DEFAULT_ARTIFACT_DIR
    end

    def user_artifact_dirs?
      @configuration.key?(:user_artifact_dirs)
    end

    def user_artifact_dirs
      @configuration.key?(:user_artifact_dirs) ? @configuration[:user_artifact_dirs].map { |d| Pathname(d) } : nil
    end

    def target_artifact_dir
      Pathname(@configuration[:target_artifact_dir] || "#{Origen.app.root}/simulation/#{Origen.target.name}/artifacts")
    end

    def artifact_run_dir
      p = Pathname(@configuration[:artifact_run_dir] || './application/artifacts')
      if p.absolute?
        p
      else
        Pathname(run_dir).join(p)
      end
    end

    def artifact_populate_method
      @configuration[:artifact_populate_method] || begin
        if Origen.running_on_windows?
          :copy
        else
          :symlink
        end
      end
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

    def wave_dir(subdir = nil)
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
      @wave_config_file ||= configuration[:wave_config_file] || begin
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
        if configuration[:verdi]
          'rc'
        else
          'tcl'
        end
      end
    end

    def run_cmd
      case config[:vendor]
      when :icarus
        cmd = configuration[:vvp] || 'vvp'
        cmd += " -M#{compiled_dir} -morigen #{compiled_dir}/origen.vvp +socket+#{socket_id}"

      when :cadence
        input_file = "#{tmp_dir}/#{wave_file_basename}.tcl"
        if !File.exist?(input_file) || config_changed?
          Origen.app.runner.launch action:            :compile,
                                   files:             "#{Origen.root!}/templates/probe.tcl.erb",
                                   output:            tmp_dir,
                                   check_for_changes: false,
                                   quiet:             true,
                                   options:           { dir: wave_dir, wave_file: wave_file_basename, force: config[:force], setup: config[:setup], depth: :all },
                                   output_file_name:  "#{wave_file_basename}.tcl"
        end
        input_file_fast = "#{tmp_dir}/#{wave_file_basename}_fast.tcl"
        if !File.exist?(input_file_fast) || config_changed?
          fast_probe_depth = config[:fast_probe_depth] || 1
          Origen.app.runner.launch action:            :compile,
                                   files:             "#{Origen.root!}/templates/probe.tcl.erb",
                                   output:            tmp_dir,
                                   check_for_changes: false,
                                   quiet:             true,
                                   options:           { dir: wave_dir, wave_file: wave_file_basename, force: config[:force], setup: config[:setup], depth: fast_probe_depth },
                                   output_file_name:  "#{wave_file_basename}_fast.tcl"
        end
        save_config_signature
        wave_dir  # Ensure this exists since it won't be referenced above if the input file is already generated

        cmd = configuration[:irun] || 'irun'
        cmd += " -r origen -snapshot origen +socket+#{socket_id}"
        cmd += $use_fast_probe_depth ? " -input #{input_file_fast}" : " -input #{input_file}"
        cmd += " -nclibdirpath #{compiled_dir}"

      when :synopsys
        if configuration[:verdi]
          cmd = "#{compiled_dir}/simv +socket+#{socket_id} +FSDB_ON +fsdbfile+#{Origen.root}/waves/#{Origen.target.name}/#{wave_file_basename}.fsdb +memcbk +vcsd"
        else
          cmd = "#{compiled_dir}/simv +socket+#{socket_id} -vpd_file #{wave_file_basename}.vpd"
        end

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

      # Print the command if debug is enabled
      Origen.log.debug 'OrigenSim Run Command:'
      Origen.log.debug cmd

      cmd
    end

    def wave_file_basename
      if OrigenSim.flow
        OrigenSim.flow.to_s
      else
        if Origen.app.current_job
          @last_wafe_file_basename = Pathname.new(Origen.app.current_job.output_file).basename('.*').to_s
        else
          if Origen.interactive?
            'interactive'
          else
            @last_wafe_file_basename
          end
        end
      end
    end

    def view_wave_command
      cmd = nil
      case config[:vendor]
      when :icarus
        edir = Pathname.new(wave_config_dir).relative_path_from(Pathname.pwd)
        cmd = "cd #{edir} && "
        cmd += configuration[:gtkwave] || 'gtkwave'
        dir = Pathname.new(wave_dir).relative_path_from(edir.expand_path)
        cmd += " #{dir}/#{wave_file_basename}/dump.vcd "
        f = Pathname.new(wave_config_file).relative_path_from(edir.expand_path)
        cmd += " --save #{f} &"

      when :cadence
        edir = Pathname.new(wave_config_dir).relative_path_from(Pathname.pwd)
        cmd = "cd #{edir} && "
        cmd += configuration[:simvision] || 'simvision'
        dir = Pathname.new(wave_dir).relative_path_from(edir.expand_path)
        cmd += " #{dir}/#{wave_file_basename}/#{wave_file_basename}.dsn #{dir}/#{wave_file_basename}/#{wave_file_basename}.trn"
        f = Pathname.new(wave_config_file).relative_path_from(edir.expand_path)
        cmd += " -input #{f} &"

      when :synopsys
        edir = Pathname.new(wave_config_dir).relative_path_from(Pathname.pwd)
        cmd = "cd #{edir} && "
        if configuration[:verdi]
          unless ENV['VCS_HOME'] && ENV['LD_LIBRARY_PATH']
            puts 'Please make sure the VCS_HOME and LD_LIBRARY PATH are setup correctly before using Verdi'
          end
          edir = Pathname.new(wave_config_dir).relative_path_from(Pathname.pwd)
          cmd = "cd #{edir} && "
          cmd += configuration[:verdi] || 'verdi'
          dir = Pathname.new(wave_dir).relative_path_from(edir.expand_path)
          cmd += " -ssz -dbdir #{Origen.root}/simulation/#{Origen.target.name}/synopsys/simv.daidir/ -ssf #{dir}/#{wave_file_basename}.fsdb"
          f = Pathname.new(wave_config_file).relative_path_from(edir.expand_path)
          cmd += " -sswr #{f}"
          cmd += ' &'
        else
          cmd += configuration[:dve] || 'dve'
          dir = Pathname.new(wave_dir).relative_path_from(edir.expand_path)
          cmd += " -vpd #{dir}/#{wave_file_basename}.vpd"
          f = Pathname.new(wave_config_file).relative_path_from(edir.expand_path)
          cmd += " -session #{f}"
          cmd += ' &'
        end

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
      when :icarus
        d = File.join(wave_dir, wave_file_basename)
        FileUtils.mkdir_p(d)
        d
      when :synopsys
        wave_dir
      else
        tmp_dir
      end
    end

    def simulation_open?
      @simulation_open
    end

    # Starts up the simulator process
    def start
      Origen.log.level = :verbose if Origen.debugger_enabled?
      @simulation_open = true
      @simulation = Simulation.new(wave_file_basename, view_wave_command)
      simulations << @simulation

      fetch_simulation_objects

      artifact.clean
      artifact.populate

      cmd = run_cmd + ' & echo \$!'

      launch_simulator = %(
        require 'open3'
        require 'socket'
        require 'io/wait'
        require 'origen'

        pid = nil

        def kill_simulation(pid)
          begin
            # If the process already finished, then we will see an Errno exception.
            # It does not harm anything, but looks ugly, so catch it here and ignore.
            Process.kill('KILL', pid)
          rescue Errno::ESRCH => e
          end
          exit!
        end

        status = UNIXSocket.new('#{simulation.socket_id(:status)}')
        stdout_socket = UNIXSocket.new('#{simulation.socket_id(:stdout)}')
        stderr_socket = UNIXSocket.new('#{simulation.socket_id(:stderr)}')
        heartbeat = UNIXSocket.new('#{simulation.socket_id(:heartbeat)}')

        begin

          status.puts('Starting the simulator...')

          Dir.chdir '#{run_dir}' do
            Open3.popen3('#{cmd}') do |stdin, stdout, stderr, thread|
              status.puts('The simulator has started')
              pid = stdout.gets.strip.to_i
              status.puts(pid.to_s)

              # Listen for a heartbeat from the main Origen process every 5 seconds, kill the
              # simulator after two missed heartbeats
              Thread.new do
                missed_heartbeats = 0
                loop do
                  sleep 5

                  # If the socket read hangs, count that as a reason to shutdown
                  socket_read = false
                  Thread.new do
                    sleep 1
                    kill_simulation(pid) unless socket_read
                  end

                  if heartbeat.ready?
                    while heartbeat.ready? do
                      heartbeat.gets
                    end
                    missed_heartbeats = 0
                  else
                    missed_heartbeats += 1
                  end
                  socket_read = true
                  if missed_heartbeats > 1
                    kill_simulation(pid)
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

          status.puts 'The simulator has finished'

        ensure
          # Make sure this process never finishes and leaves the simulator running
          kill_simulation(pid) if pid
        end
      )

      Origen.log.debug 'Starting the simulation monitor...'

      monitor_pid = spawn("ruby -e \"#{launch_simulator}\"")
      Process.detach(monitor_pid)

      simulation.open(monitor_pid, config[:startup_timeout] || 60) # This will block until the simulation process has started

      # The VPI extension will send 'READY!' when it starts, make sure we get it before proceeding
      data = get
      unless data.strip == 'READY!'
        simulation.failed_to_start = true
        simulation.log_results
        exit  # Assume it is not worth trying another pattern in this case, some kind of environment/config issue
      end
      Origen.log.info "OrigenSim version #{Origen.app!.version}"
      Origen.log.info "OrigenSim DUT version #{dut_version}"
      # Tick the simulation on, this seems to be required since any VPI puts operations before
      # the simulation has started are not applied.
      # Note that this is not setting a tester timeset, so the application will still have to
      # do that before generating any vectors.
      set_period(100)
      cycle(1)
      Origen.listeners_for(:simulation_startup).each(&:simulation_startup)
    end

    # Send the given message string to the simulator
    def put(msg)
      simulation.socket.write(msg + "\n")
    rescue Errno::EPIPE => e
      if simulation.running?
        Origen.log.error 'Communication with the simulator has been lost (though it seems to still be running)!'
      else
        Origen.log.error 'The simulator has stopped unexpectedly!'
      end
      sleep 2 # To make sure that any log output from the simulator is captured before we pull the plug
      exit 1
    end

    # Get a message from the simulator, will block until one
    # is received
    def get
      simulation.socket.readline
    end

    # At the start of a test program flow generation/simulation
    def on_flow_start(options)
      if simulation_tester? && options[:top_level]
        @flow_running = true
        OrigenSim.flow = Origen.interface.flow.name
        start
        @pattern_count = 0
      end
    end

    # At the end of a test program flow generation/simulation
    def on_flow_end(options)
      if simulation_tester? && options[:top_level]
        @flow_running = false
        simulation.completed_cleanly = true
        stop
      end
    end

    # Called before every pattern is generated, but we only use it the
    # first time it is called to kick off the simulator process if the
    # current tester is an OrigenSim::Tester
    def before_pattern(name)
      if simulation_tester?
        if OrigenSim.flow || !simulation
          # When running patterns back-to-back, only want to launch the simulator the first time
          start unless simulation
        else
          simulation.completed_cleanly = true
          stop
          start
        end
        # Set the current pattern name in the simulation
        put("a^#{name.sub(/\..*/, '')}")
        @pattern_count ||= 0
        # If running a flow, give the user some feedback about pass/fail status after
        # each individual pattern has completed
        if @pattern_count > 0 && OrigenSim.flow
          simulation.log_results(true)
          # Require each pattern to set this upon successful completion
          simulation.completed_cleanly = false unless @flow_running
        end
        @pattern_count += 1
      end
    end

    # This will be called at the end of every pattern, make
    # sure the simulator is not running behind before potentially
    # moving onto another pattern
    def pattern_generated(path)
      if simulation_tester?
        sync_up
        simulation.completed_cleanly = true unless @flow_running
      end
    end

    def write_comment(line, comment)
      return if line >= OrigenSim::NUMBER_OF_COMMENT_LINES
      # Not sure what the limiting factor here is, the comment memory in the test bench should
      # be able to handle 1024 / 8 length strings, but any bigger than this hangs the simulation
      comment = comment ? comment[0..96] : ''
      if dut_version > '0.12.1'
        put("c^#{line}^#{comment} ")  # Space at the end is important so that an empty comment is communicated properly
      else
        put("c^#{comment} ")
      end
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

    # Flush any buffered simulation output, this should cause live wave viewers to
    # reflect the latest state
    def flush
      if dut_version > '0.12.0'
        put('j^')
        sync_up
      else
        OrigenSim.error "Use of flush requires a DUT model compiled with OrigenSim version > 0.12.0, the current dut was compiled with #{dut_version}"
      end
    end

    def error(message)
      simulation.logged_errors = true
      Origen.log.error message
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
      @simulation_open = false
      simulation.error_count = error_count
      Origen.listeners_for(:simulation_shutdown).each(&:simulation_shutdown)
      end_simulation
      # Give the simulator time to shut down
      sleep 0.1 while simulation.running?
      simulation.close
      simulation.log_results unless Origen.current_command == 'interactive'
    rescue
      simulation.completed_cleanly = false
    end

    def on_origen_shutdown
      unless simulations.empty?
        failed = false
        stop if simulation_open?
        unless @interactive_mode
          if simulations.size == 1
            failed = simulation.failed?
          else
            failed_simulation_count = simulations.count(&:failed?)
            if failed_simulation_count > 0
              Origen.log.error "#{failed_simulation_count} of #{simulations.size} simulations failed!"
              failed = true
            end
          end
          if failed
            Origen.app.stats.report_fail
          else
            Origen.app.stats.report_pass
          end
        end
        puts
        if simulations.size == 1
          puts 'To view the simulation run the following command:'
          puts
          puts "  #{simulation.view_wave_command}"
        else
          puts 'To view the simulations run the following commands:'
          puts
          simulations.each do |simulation|
            if simulation.failed?
              puts "  #{simulation.view_wave_command}".red
            else
              puts "  #{simulation.view_wave_command}"
            end
          end
        end
        puts
        unless @interactive_mode
          failed ? exit(1) : exit(0)
        end
      end
    end

    def socket_id
      simulation.socket_id
    end

    def simulation_tester?
      (tester && tester.is_a?(OrigenSim::Tester))
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

    # Any vectors executed within the given block will increment the match_errors counter
    # rather than the errors counter.
    # The match_errors counter will be returned to 0 at the end.
    def match_loop
      poke("#{testbench_top}.pins.match_loop", 1)
      yield
      poke("#{testbench_top}.pins.match_loop", 0)
      poke("#{testbench_top}.pins.match_errors", 0)
    end

    def match_errors
      peek("#{testbench_top}.pins.match_errors").to_i
    end

    private

    # Pre 0.8.0 the simulator represented the time in ns instead of ps
    def time_conversion_factor
      @time_conversion_factor ||= dut_version < '0.8.0' ? 1 : 1000
    end

    def clean(net)
      if net =~ /^dut\./
        "#{testbench_top}.#{net}"
      else
        net
      end
    end
  end
end
