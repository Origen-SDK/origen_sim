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

