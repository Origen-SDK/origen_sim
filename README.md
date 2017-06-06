# origen_sim

origen_sim is an Origen plugin that enables semiconductor test patterns written in Origen/Ruby to be run in a dynamic Verilog simulation.
Origen/Ruby is in charge of a Verilog simulation process that is run in parallel, with the Origen process deciding when the
simulation time should advance and by how much.
This relationship allows regular Ruby debugger breakpoints to be inserted into the pattern source code in order to halt the simulation
at a specific point in time, and from there it can be interatively debugged at the Ruby-source-code level.

For documentation on how to use origen_sim, see the website: http://origen-sdk.org/sim

This document describes the technical details of how origen_sim works to help enable engineers to contribute to its development.

### Summary Of Operation

origen_sim provides components that can be compiled into a simulation object along with the design under test (DUT). 

