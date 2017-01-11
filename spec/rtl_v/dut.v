`include "tap_top.v"
`include "counter.v"

module dut(tck,tdi,tdo,tms,trstn,
            rstn,
            done,
            test_bus
          );

  input tck, tdi, tms, trstn;
  input rstn;

  output tdo;
  output done;
  output [15:0] test_bus;

  wire [4:0] count;

  // Used for testing peek and poke methods
  reg [15:0] test_data;
  assign test_bus = test_data;

  tap_top tap (
    .tms_pad_i(tms),
    .tck_pad_i(tck),
    .tdi_pad_i(tdi),
    .tdo_pad_o(tdo),
    .trstn_pad_i(trstn & rstn)
  );

  counter counter (
    .clock(tck),
    .reset(!rstn),
    .count(count)
  );

endmodule
