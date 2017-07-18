# origen_sim

origen_sim is an Origen plugin that enables semiconductor test patterns written in Origen/Ruby to be run in a dynamic Verilog simulation.
Origen/Ruby is in charge of a Verilog simulation process that is run in parallel, with the Origen process deciding when the
simulation time should advance and by how much.
This relationship allows regular Ruby debugger breakpoints to be inserted into the pattern source code in order to halt the simulation
at a specific point in time, and from there it can be interatively debugged at the Ruby-source-code level.

For documentation on how to use origen_sim, see the website: http://origen-sdk.org/sim

This document describes the technical details of how origen_sim works to enable engineers to contribute to its future development.

### Summary Of Operation

origen_sim provides components that can be compiled into a simulation object along with the design under test (DUT), and a high level view of the process looks like this:

![image](https://user-images.githubusercontent.com/158364/28324051-6a149088-6bd2-11e7-936d-49ec87b2c0bb.png)

The main Origen Ruby process is invoked by generating a pattern as usual, e.g. <code>origen g my_pattern</code>, but with the environment setup to instantiate an instance of <code>OrigenSim::Tester</code> as the tester instead of say <code>OrigenTesters::V93K</code> which would be used to generate an ATE pattern output.



The testbench 


### The Testbench

### The VPI Extension

### Register Syncing


