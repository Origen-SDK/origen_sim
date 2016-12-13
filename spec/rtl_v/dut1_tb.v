`include "dut1.v"

`timescale 100ns/1ns

module dut1_tb;

  reg tck, tdi, tms, trstn;
  wire tdo;
  reg rstn;

  dut1 dut (
    .tck(tck),
    .tdi(tdi),
    .tms(tms),
    .trstn(trstn),
    .tdo(tdo),
    .rstn(rstn)
  );

  initial
  begin
    $dumpfile("dut1.vcd");
    $dumpvars(0,dut1_tb);

    //$monitor("%d,\t%b",$time, tck);
  end

  initial
  begin
    tck = 0;
    tdi = 0;
    tms = 0;
    trstn = 0;
    rstn = 0;

    #10 rstn = 1;
    #100 trstn = 1;

    #1000 $finish;
  end

  always 
    #0.5 tck = !tck;


endmodule
