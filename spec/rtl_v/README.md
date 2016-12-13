## To Run an Icarus Verilog Simulation

~~~text
iverilog -o tmp dut1_tb.v        // Compile the RTL/testbench
vvp tmp                          // Run the simulation
gtkwave dut1.vcd                 // View the waves
~~~


