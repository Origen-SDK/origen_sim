![origen_sim](https://user-images.githubusercontent.com/158364/36662666-6b49d096-1adf-11e8-997e-889caba391b2.png)

For user documentation see - [http://origen-sdk.org/origen/guides/simulation/introduction](http://origen-sdk.org/origen/guides/simulation/introduction)

Here is some OrigenSim developer information...

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

OrigenSim provides two further customizations to the default setup. Like the target directory, you can pass additional
<code>user_artifact_dirs</code>, which will override any artifacts found at either the default or target artifact levels.
These artifacts will override each other in the order of the Array definition.

All of these artifacts have different sources, but they are placed in the same <code>artifact_run_dir</code>, which
defaults to <code>application/artifacts</code>. This location is customizable as well with the <code>artifact_run_dir</code>
option.

~~~ruby
OrigenSim::cadence do |sim|
  # Add a user artifact directory
  sim.user_artifact_dirs ["#{Origen.app.root}/simulation/testbench"]

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

Additional single-artifact items can be added manually:

~~~ruby
# in environment/sim.rb

tester = OrigenSim::cadence do |sim|
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


