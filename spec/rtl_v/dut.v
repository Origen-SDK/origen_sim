`include "tap_top.v"
`include "counter.v"

module dut1(tck,tdi,tdo,tms,trstn,
            rstn,
            done,
          );

  input tck, tdi, tms, trstn;
  input rstn;

  output tdo;
  output done;

  wire [4:0] count;

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
