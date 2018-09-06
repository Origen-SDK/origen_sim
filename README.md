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

### The VPI Extension

#### Configuring The VPI

### Register Syncing


