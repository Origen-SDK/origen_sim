`include "counter.v"

`timescale 1ns/1ns

module tb;

  reg clock, reset;
  wire [4:0] count;

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
