`include "dut.v"

`timescale 1ns/1ns

// 0 - Data
// 1 - Reserved 
//
// 0 - Drive
//
// 0 - Compare
//
// 0 - Force data 0
// 1 - Force data 1
module pin_driver(error, pin);

  output reg error;

  inout pin;

  reg [1:0] data = 0;
  reg [1:0] force_data = 0;
  reg compare = 0;
  reg drive = 0;
  reg [1023:0] memory = 0;

  wire drive_data = force_data[0] ? 0 : (force_data[1] ? 1 : data[0]);

  assign pin = drive ? drive_data : 1'bz;

  // Debug signal to show the expected data in the waves
  wire expect_data = compare ? data[0] : 1'bz;

  always @(*) begin
    error = compare ? (pin == data[0] ? 0 : 1) : 0;
  end

endmodule

module pin_drivers(tck_o, tdi_o, tdo_o, tms_o, rstn_o, trstn_o);

  output tck_o;
  output tdi_o;
  output tdo_o;
  output tms_o;
  output rstn_o;
  output trstn_o;

  wire tck_err;
  wire tdi_err;
  wire tdo_err;
  wire tms_err;
  wire rstn_err;
  wire trstn_err;

  output reg [31:0] errors_o = 0;

  always @(

    posedge tck_err
    or posedge tdi_err
    or posedge tdo_err
    or posedge tms_err
    or posedge rstn_err
    or posedge trstn_err
  ) begin
    errors_o[31:0] = errors_o[31:0] + 1;
  end

  pin_driver tck (.pin(tck_o), .error(tck_err));
  pin_driver tdi (.pin(tdi_o), .error(tdi_err));
  pin_driver tdo (.pin(tdo_o), .error(tdo_err));
  pin_driver tms (.pin(tms_o), .error(tms_err));
  pin_driver rstn (.pin(rstn_o), .error(rstn_err));
  pin_driver trstn (.pin(trstn_o), .error(trstn_err));

endmodule


module debug(errors);

  input [31:0] errors;

  reg [1023:0] pattern = 0;

  reg handshake;

endmodule

module origen_tb;

  wire tck;
  wire tdi;
  wire tdo;
  wire tms;
  wire rstn;
  wire trstn;

  wire [31:0] errors;

  pin_drivers pins (
    .tck_o(tck),
    .tdi_o(tdi),
    .tdo_o(tdo),
    .tms_o(tms),
    .rstn_o(rstn),
    .trstn_o(trstn)
  );

  dut dut (
    .tck(tck),
    .tdi(tdi),
    .tdo(tdo),
    .tms(tms),
    .rstn(rstn),
    .trstn(trstn)
  );

  debug debug (
    .errors(errors)
  );

  initial
  begin
    $dumpfile("dut.vcd");
    $dumpvars(0,origen_tb);
  end

endmodule
