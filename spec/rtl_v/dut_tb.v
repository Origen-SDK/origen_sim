`include "dut.v"

`timescale 1ns/1ns

// 0 - Data
// 1 - Reserved 
// 2 - Reserved
// 3 - Reserved
// 4 - Drive
// 5 - Compare
// 6 - Capture
//
// 0 - Force data 0
// 1 - Force data 1
module pin_driver(comparing, capturing, driving, error, pin);

  output comparing;
  output capturing;
  output driving;
  output reg error;

  inout pin;

  reg [6:0] control = 0;
  reg [1:0] force_data = 0;
  reg [1023:0] memory = 0;

  wire drive_data = force_data[0] ? 0 : (force_data[1] ? 1 : control[0]);

  assign pin = driving ? drive_data : 1'bz;

  assign driving = control[4];

  assign comparing = control[5];

  assign capturing = control[6];

  always @(control or pin) begin
    error = control[5] ? (pin == control[0] ? 0 : 1) : 0;
  end

endmodule

module pin_drivers(tck_o, tdi_o, tms_o, trstn_o, rstn_o, tdo_o, done_o, errors_o);

  output tck_o;
  output tdi_o;
  output tms_o;
  output trstn_o;
  output rstn_o;
  output tdo_o;
  output done_o;

  wire tck_err;
  wire tdi_err;
  wire tms_err;
  wire trstn_err;
  wire rstn_err;
  wire tdo_err;
  wire done_err;

  output reg [31:0] errors_o = 0;

  always @(posedge tck_err or posedge tdi_err or posedge tms_err or posedge trstn_err or
           posedge rstn_err or posedge tdo_err or posedge done_err) begin
    errors_o[31:0] = errors_o[31:0] + 1;
  end

  pin_driver tck (.pin(tck_o), .error(tck_err));
  pin_driver tdi (.pin(tdi_o), .error(tdi_err));
  pin_driver tms (.pin(tms_o), .error(tms_err));
  pin_driver trstn (.pin(trstn_o), .error(trstn_err));
  pin_driver rstn (.pin(rstn_o), .error(rstn_err));
  pin_driver tdo (.pin(tdo_o), .error(tdo_err));
  pin_driver done (.pin(done_o), .error(done_err));

endmodule


module debug(errors);

  input [31:0] errors;

  reg [1023:0] pattern = 0;

  reg handshake;

endmodule

module origen_tb;


  wire tck;
  wire tdi;
  wire tms;
  wire trstn;
  wire rstn;
  wire tdo;
  wire done;

  wire [31:0] errors;

  pin_drivers pins (
    .tck_o(tck),
    .tdi_o(tdi),
    .tms_o(tms_drv),
    .trstn_o(trstn),
    .tdo_o(tdo),
    .rstn_o(rstn),
    .done_o(done),

    .errors_o(errors)
  );

  dut dut (
    .tck(tck),
    .tdi(tdi),
    .tms(tms_drv),
    .trstn(trstn),
    .tdo(tdo),
    .rstn(rstn),
    .done(done)
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
