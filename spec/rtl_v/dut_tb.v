`include "dut.v"

`timescale 1ns/1ns

module origen_tb;

  //************************************
  // INPUTS
  //************************************
  // Holds the vector data
  reg tck_d, tdi_d, tms_d, trstn_d, rstn_d;
  // When written to 1, will override the given
  // data to 0
  reg tck_f0, tdi_f0, tms_f0, trstn_f0, rstn_f0;
  // When written to 1, will override the given
  // data to 1
  reg tck_f1, tdi_f1, tms_f1, trstn_f1, rstn_f1;

  wire tck = tck_f0 ? 0 : (tck_f1 ? 1 : tck_d);
  wire tdi = tdi_f0 ? 0 : (tdi_f1 ? 1 : tdi_d);
  wire tms = tms_f0 ? 0 : (tms_f1 ? 1 : tms_d);
  wire trstn = trstn_f0 ? 0 : (trstn_f1 ? 1 : trstn_d);
  wire rstn = rstn_f0 ? 0 : (rstn_f1 ? 1 : rstn_d);

  initial
  begin
    tck_f0 = 0;
    tdi_f0 = 0;
    tms_f0 = 0;
    trstn_f0 = 0;
    rstn_f0 = 0;
    tck_f1 = 0;
    tdi_f1 = 0;
    tms_f1 = 0;
    trstn_f1 = 0;
    rstn_f1 = 0;
  end

  //************************************
  // OUTPUTS
  //************************************
  wire tdo;
  wire done;



  //************************************
  // DUT
  //************************************
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
    $dumpfile("dut.vcd");
    $dumpvars(0,origen_tb);
  end

endmodule
