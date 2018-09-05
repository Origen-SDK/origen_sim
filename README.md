![origen_sim](https://user-images.githubusercontent.com/158364/36662666-6b49d096-1adf-11e8-997e-889caba391b2.png)

origen_sim is an Origen plugin that enables semiconductor test patterns written in Origen/Ruby to be run in a dynamic Verilog simulation.

It provides a simulation tester driver which replaces the conventional Origen ATE tester drivers in order to pass requests to drive or expect pin values onto a simulator intead of rendering them to an ASCII file. Since the application-level Origen code is the same in both cases it guarantees that what happens in the simulation and in the final pattern are the same.

For debugging, origen_sim supports the injection of regular Ruby debugger breakpoints anywhere in the pattern source code. This will halt the simulation
at the given point in time and thereby allow it to be interatively debugged at the Ruby-source-code level.

For further documentation on how to use origen_sim and to learn about its capabilities, see the website: http://origen-sdk.org/sim

### How To Create a Simulation Object For Development of OrigenSim

From an OrigenSim workspace:

Select the environment you wish to use, e.g.:

~~~
origen e environment/cadence.rb
~~~

Run the following command to build a simulation object from [this example device](https://github.com/Origen-SDK/example_rtl/blob/master/dut1/dut1.v):

~~~
origen sim:build_example
~~~

Run a simulation to check that it is working:

~~~
origen g test
~~~

Repeat the above steps to recompile after making any changes to the VPI extension.


### Summary Of Operation

Here are some technical details on how origen_sim works, hopefully with enough detail to enable other engineers to contribute to its future development.

origen_sim provides components that can be compiled into a simulation object along with the design under test (DUT), a high level view of the process looks like this:

![image](https://user-images.githubusercontent.com/158364/28324051-6a149088-6bd2-11e7-936d-49ec87b2c0bb.png)

The main Origen Ruby process is invoked by generating a pattern as usual, e.g. <code>origen g my_pattern</code>, but with the environment setup to instantiate an instance of <code>OrigenSim::Tester</code> instead of say <code>OrigenTesters::V93K</code>.
The origen_sim tester will start off a Verilog process in parallel which will run a simulation on an object that has been created beforehand. This simulation object contains the DUT wrapped in an Origen testbench, and which has been compiled into a snapshot/object that also includes a [Verilog VPI](https://en.wikipedia.org/wiki/Verilog_Procedural_Interface) extension which provides a communication interface between Origen and the simulation world.

When the simulation process starts, the VPI extension immediately takes control and halts the simulator while it listens for further instructions from a Linux socket which was setup by origen_sim at the same time that the simulation was started.
As the Origen pattern generation process executes, the <code>OrigenSim::Tester</code> will translate any requests to drive or expect pin values, or to generate a cycle, into messages which are passed into the Linux socket. Upon receving these messages, the VPI process will manipulate the testbench's pin drivers to drive or read from the DUT and it will advance time by a cycle period every time a cycle is generated in the pattern.
The testbench to wrap and instantiate the DUT is generated by origen_sim and it provides a standard interface through which Origen can access any DUT.

In principle the DUT object can be any design that is wrapped by a conventional top-level RTL description. Meaning that origen_sim can be used to run digital simulations, or mixed-signal simulations on DUT objects that contain more complex analog modelling.

### The Testbench

The testbench is quite simple and it does little more than instantiate the DUT module and connects all of its pins to instances of [this pin driver module](https://github.com/Origen-SDK/origen_sim/blob/master/templates/rtl_v/origen.v.erb#L14).
The testbench module is named 'origen' and all origen_sim simulation dumps have this same top-level structure:

~~~
origen
     |--debug        # Contains an error count and other debug aids
     |--dut          # The DUT top-level
     |--pins         
           |--tdi    # Driver for the TDI pin (for example)
           |--tdo    # Driven for the TDO pin and so on
           |--tck
~~~



The driver contains a number of registers which are written to directly by the VPI process, allowing it to drive or expect a given data value (stored in <code>origen.pins.\<pin\>.data</code>) by writing a 1 to <code>origen.pins.\<pin\>.drive</code> or <code>origen.pins.\<pin\>.compare respectively</code>.
If the value being driven by the pin does match the expect data during a cycle, then an error signal will be asserted by the driver and this will increment an error counter that lives in <code>origen.debug.errors[31:0]</code>.

### Toolchains

Running the testbench along with the VPI takes place within the toolchain. Different toolchains have different setups
and different compilation and running procedures. Below is summary of some of the supported toolchains and notes on how
to use them with OrigenSim.

<anchor>cadence</anchor>
<anchor>irun</anchor>
#### Cadence (irun)

#### Synopsis

#### Generic

Generic toolchains allow you to use a tool that is not support out of the box by <code>OrigenSim</code>. For these, it 
is your responsiblity to provide the command to start the VPI process, however, this allows for arbitrary commands to
start the process and allows end users to still use <code>origen g</code> as if with an <code>OrigenSim</code> supported toolchain.

An example of such a setup could be:

~~~ruby
OrigenSim.generic do |sim|
  # Set a 5 minute connection timeout
  sim.startup_timeout 300

  sim.generic_run_cmd do |s|
    # Return the command to start the testbench.
    "path/to/custom/sim/script +socket+#{s.socket_id}"
  end
end
~~~

An example using the predecessor of the supported Cadence tool <code>irun</code>, <code>ncsim</code> is shown below.

~~~ruby
OrigenSim.generic(startup_timeout: 900) do |sim|
  sim.testbench_top 'na_origen'
  sim.generic_run_cmd do |s|
    "ncsim na_origen -loadpli origen.so:bootstrap +socket+#{s.socket_id}"
  end
end
~~~

### Configuring The Toolchain (Vendor)

When you define a toolchain, you can pass in additional arguments to customize the toolchain and how OrigenSim interacts
with the toolchain.

A non-exhaustive list (to be updated in the future) is below:

* testbench_top: Defines the testbench name if different from <code>origen</code>.
* view_waveform_cmd: Required for generic toolchains - prints out this statement following a simulation instructing the
user on how to open the waveforms for viewing. For supported toolchains, this is already provided, but can be overwritten.
* startup_timeout: Defines how long (in seconds) OrigenSim will wait for VPI interaction on the socket before it terminates
and returns an error.
* generic_run_cmd: Either a string, array to be joined by ' && ', or a block returning either of the aforementioned that
the generic toolchain (vendor) will use to begin the testbench toolchain process.
* post_process_run_cmd: Block object to post-process the cmd OrigenSim will start the testbench with. This can be used
to post-process the command for any supported vendor. This block should return the command to run, as a string.

An example of the <code>post_process_run_cmd</code> usage is:

~~~ruby
OrigenSim.cadence do |sim|
  sim.post_process_run_cmd do |cmd, s|
    # cmd is the current command that will be run. s is the simulator object, same as sim in this case.
    # this should return either a string or an array to be joined by ' && ' (chain commands)
    # note that we must RETURN the string. We cannot just edit it.
    
    # add an environment variable and run setup script as an example
    return "export PROJECT=my_rtl && source #{Origen.app.root.join('settings.sh')} && #{cmd}"
    
    # or, we could return
    return [
      'export PROJECT=my_rtl',
      "source #{Origen.app.root.join('settings.sh')}",
      cmd
    ]
    #=> "export PROJECT=my_rtl && source #{Origen.app.root.join('settings.sh')} && #{cmd}"
  end
end
~~~

### Running and Configuring OrigenSim

#### Monitoring Errors and Warnings

While OrigenSim is running, it will be monitoring the output of the testbench process that it starts. This is to ensure
that the process doesn't fail unexpectedly or become orphaned, and to check the results of the simulation itself.

The pattern will report a <code>pass/fail</code> result, checking all <code>read!</code> or <code>asser!</code>
operations performed in the
pattern. In the event of failures, the error count will be reported and the Ruby process will "fail", meaning the
simulation failed, or did not complete as expected.

OrigenSim will also monitor the log from <code>stdout</code> and <code>stderr</code>. If anything is written to
<code>stderr</code>, the simulation will fail. However, this is not always the desired behavior. Verilog process can write to
<code>stderr</code> themselves. Sometimes, these <code>stderr</code> writes are non-valid, or non-concerning. One workaround
is to tell OrigenSim to ignore any <code>stderr</code> output:

~~~ruby
OrigenSim.fail_on_stderr = false
~~~

However, this will blanket-ignore all <code>stderr</code>. A safer, but more involved, solution is to instead dictate
which strings are acceptable from <code>stderr</code>. 

For example, in an early testbench
release, the ADC is not configured correctly. However, we are aware of this, and it does not affect us, and we do
not wish to fail the simulation due to these errors. We can include substrings which, if included in the
<code>stderr</code> lines, are not logged as errors (note that these are case-sensitive):

~~~ruby
OrigenSim.stderr_string_exceptions += ['invalid adc config', 'invalid ADC config']
~~~

A similar situation arises with the log. OrigenSim will parse the logged output on <code>stdout</code> and if a line
matches anything in <code>OrigenSim.error_strings</code>, the simulation will fail. By default, this will include
just a single string: <code>'ERROR'</code>, but others can be added.

However, <code>'ERROR'</code> is quite broad. An example of an error we may see here, but do not actually want to fail
the simulation for, is uninitialized memory. This is common with ROMs in early testbench revisions, before
the ROM is actually complete. This can be remedied similar to <code>stderror</code> using:

~~~ruby
OrigenSim.error_string_exceptions << 'uninitialized value in ROM at'
~~~

This means a log line resembling <code>ERROR uninitialized value in ROM at 0x1000</code> will not fail the simulation.
Neither will the line <code>ERROR uninitialized value in ROM at 0x1004</code> or
<code>ERROR uninitialized value in ROM at 0x1008</code>, but the line 
<code>ERROR uninitialized value in RAM at 0x2000</code> will fail. This can be used to catch unexpected Verilog errors, 
while ignoring known ones that you've consciously decided do not affect your simulations.

#### The Run Directory

The simulator is kicked off, not at the snapshot directory, but at a vender-specific custom directory. The run
directory will be set when the simulator is initialized, and can be queried either by the pattern or in an interactive
session using <code>Origen.tester.simulator.run_dir</code>.

For example, when the Cadence vendor is used:

~~~ruby
Origen.tester.simulator.run_dir
  #=> "/path/to/the/current/app/tmp/origen_sim/default/cadence"
~~~

#### Artifacts

When OrigenSim runs, it will change the current directory to the <code>run_dir</code>. This is not necessarily the
same directory that the compiled snapshot resides in and will most likely break relative paths compiled into the
snapshot.

OrigenSim provides an <code>artifacts</code> API to handle this problem. <code>Artifacts</code> are just files or
directories that need to be available in the <code>run_dir</code> prior to the simulation start. This can be used to
reconstruct the run directory regardless of vendor or target configurations, and without requiring you to build in the
logic into the application itself.

OrigenSim will automatically look for artifacts in the directory <code>#{Origen.app.root}/simulation/application/artifacts</code>.
Anything in the this folder will be moved to the run directory and placed in <code>application/artifacts</code> just before the
simulation process starts. These artifacts will be populated across targets. You can override an artifact with one
specific to your target by placing an artifact with the same name in <code>simulation/\<target\>/artifacts</code>. 

For example, if I have an artifact <code>simulation/application/artifacts/startup.sv</code> that I need for 
three targets, <code>rtl</code>, <code>part_analog</code>, and <code>all_analog</code>, this same artifact will be used
whenever any of those targets are used. Then, consider I have a new target <code>gate</code>, which has a different
<code>startup.sv</code> to run. By placing this at <code>simulation/gate/artifacts/startup.sv</code>, OrigenSim
will replace the artifact in <code>simulation/application/artifacts</code> with this one, in the same <code>run_dir</code>.

Warning: Default artifacts only go a single level deep. Directories placed at <code>simulation/\<target\>/artifacts</code>
will override an entire directory at <code>application/artifacts</code>. If you need more
control over the artifacts, you can see further down in this guide for manually adding artifacts.

You can customize these directories when instantiating the environment. For example:

~~~ruby
OrigenSim::cadence do |sim|
  # Change the default artifact directory
  sim.artifact_dir "#{Origen.app.root}/simulation/testbench"

  # Change the artifact target location, within the context of the run directory.
  # NOTE: this is relative to the run_dir. This expands to /path/to/run/dir/testbench
   sim.artifact_run_dir "./testbench"
end
~~~

Note here that the <code>artifact_run_dir</code> is <b>implicitly relative</b> to the
<code>run_dir</code>. Relative paths are expanded in the context of the <code>run_dir</code>, <b>not</b> relative to
the current script location.

Artifacts can be populated either by symlinks or by copying the contents directly. By default, Linux will symlink the
contents and unlink to clean them. However, due to the elevated priveledges required by later Windows systems to symlink objects,
the default behavior for Windows is to just copy files. This does mean that larger, and/or a large number, of artifacts
may take longer. This behavior can be changed however:

~~~ruby
OrigenSim::cadence do |sim|
  # Force all artifacts to be copied
  artifact_populate_method :copy
	
  # Force all artifacts to be symlinked
  artifact_populate_method :symlink
end
~~~

OrigemSim's artifacts can be queried, populated, or cleaned, directly by accessing the <code>OrigenSim.artifact</code>
object (note: the exclusion of the <i>s</i>). Some methods also exist to retrieve and list the current artifacts:

~~~ruby
# Populate all the artifacts
tester.simulator.artifact.populate

# Clean the currently populated artifacts
tester.simulator.artifact.clean

# List the current artifact names
tester.simulator.list_artifacts

# Retrieve the current artifact instances (as a Hash whose keys are the names returned above)
tester.simulator.artifacts

# Retrieve a single artifact
tester.simulator.artifacts[my_artifact]
tester.simulator.artifact[my_artifact]
~~~

The <code>OrigenSim::Artifacts</code> class inherits from
[Origen::Componentable](http://origen-sdk.org/origen/guides/models/componentable/#The_Parent_Class),
so any of the <i>componentable</i> methods are available.

Additional artifacts can be added to any that the default <code>artifact_dir</code> picks up:

~~~ruby
# in environment/sim.rb

tester = OrigenSim::cadence do |sim|
  # Force all artifacts to be copied
  artifact_populate_method :copy

  # Force all artifacts to be symlinked
  artifact_populate_method :symlink
end

tester.simulator.artifact(:my_artifact) do |a|
  # Point to a custom target
  a.target "/path/to/my/artifact.mine"

  # Point to a custom run target
  # Recall this will expand to /path/to/run/dir/custom_artifacts
  # This ultimately places the artifact at /path/to/run/dir/custom_artifacts/artifact.mine
  a.run_target "./custom_artifacts"

  # Indicate this artifact should be copied, regardlesss of global/OS settings.
  a.populate_method :copy
end
~~~

Note that this takes place <b>outside</b> of the initial tester instantiation, but can still occur in the environment
file.

### The VPI Extension

#### Configuring The VPI

### Register Syncing


