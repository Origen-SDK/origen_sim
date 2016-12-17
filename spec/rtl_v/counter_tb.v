`include "counter.v"

`timescale 1ns/1ns

module tb;

  //************************************
  // INPUTS
  //************************************
  // Holds the vector data
  reg clock_d, reset_d;
  // When written to 1, will override the given
  // data to 0
  reg clock_f0, reset_f0;
  // When written to 1, will override the given
  // data to 1
  reg clock_f1, reset_f1;

  wire clock = clock_f0 ? 0 : (clock_f1 ? 1 : clock_d);
  wire reset = reset_f0 ? 0 : (reset_f1 ? 1 : reset_d);

  initial
  begin
    clock_f0 = 0;
    reset_f0 = 0;
    clock_f1 = 0;
    reset_f1 = 0;
  end


  //************************************
  // OUTPUTS
  //************************************
  wire [4:0] count;



  //************************************
  // DUT
  //************************************
  counter dut (
    .reset(reset),
    .clock(clock),
    .count(count)
  );

  initial
  begin
    $dumpfile("dut.vcd");
    $dumpvars(0,tb);

    //$monitor("%d,\t%b",$time, tck);
  end

  //initial
  //begin
  //  reset = 1;
  //  clock = 0;

  //  #10 reset = 0;
  //  #1000 $finish;
  //end

  //always 
  //  #0.5 clock = !clock;

endmodule
