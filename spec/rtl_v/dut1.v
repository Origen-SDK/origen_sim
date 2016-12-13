`include "tap_top.v"

module dut1(tck,tdi,tdo,tms,trstn,
            rstn,
            done,
          );

  input tck, tdi, tms, trstn;
  output tdo;
  output done;

  input rstn;

  tap_top tap (
    .tms_pad_i(tms),
    .tck_pad_i(tck),
    .tdi_pad_i(tdi),
    .tdo_pad_o(tdo),
    .trstn_pad_i(trstn & rstn)
  );


endmodule
