`ifndef PARAM_OVERRIDE
`include "params.v"
`endif

module dut (
  input enable,
  input [`NUMADDR-1:0] soc_addr,

  output [31:0] port_a,
  output [15:0] port_b
);

endmodule
