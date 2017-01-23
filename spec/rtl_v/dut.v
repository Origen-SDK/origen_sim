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

  wire [31:0] count;
  wire shift_dr;
  wire debugger_en;
  wire tdi_o;
  wire debug_tdo_i;
  wire capture_dr;
  wire update_dr;
  wire [31:0] address;
  wire [31:0] data;
  wire rw_en;
  wire read_en;
  wire count_clk;
  wire count_en;
  wire count_reset;

  // Used for testing peek and poke methods
  reg [15:0] test_data;
  assign test_bus = test_data;

  tap_top tap (
    .tms_pad_i(tms),
    .tck_pad_i(tck),
    .tdi_pad_i(tdi),
    .tdo_pad_o(tdo),
    .trstn_pad_i(trstn & rstn),
    .shift_dr_o(shift_dr),
    .debug_select_o(debugger_en),
    .tdi_o(tdi_o),
    .debug_tdo_i(debug_tdo_i),
    .update_dr_o(update_dr),
    .capture_dr_o(capture_dr)
  );

  counter counter (
    .clock(count_clk),
    .reset(count_reset),
    .count(count)
  );

  //****************************************************************
  // DEBUGGER INTERFACE
  //****************************************************************
  reg [65:0] dr;

  // DR shift register
  always @ (posedge tck or negedge rstn) begin
    if (rstn == 0)
      dr[65:0] <= 66'b0;
    else if (shift_dr == 1 && debugger_en == 1)
      begin
        dr[65] <= tdi_o;
        dr[64:0] <= dr[65:1];
      end
    else
      dr[65:0] <= dr[65:0];
  end

  assign rw_en = dr[65];
  assign read_en = dr[64];
  assign address[31:0] = dr[63:32];
  assign data[31:0] = dr[31:0];
  assign debug_tdo_i = dr[0];
  assign write_register = update_dr && debugger_en && !read_en && rw_en;
  assign read_register = capture_dr && debugger_en && read_en && rw_en;

  //****************************************************************
  // DEVICE REGISTERS
  //****************************************************************

  reg [31:0] ctrl;  // Address 0

  always @ (negedge tck or negedge rstn) begin
    if (rstn == 0)
      ctrl[31:0] <= 32'b0;
    else if (write_register && address == 32'b0)
      ctrl[31:0] <= data;
    else
      ctrl[31:0] <= ctrl[31:0];
  end

  assign count_en = ctrl[0];
  assign count_reset = ctrl[1];
  assign count_clk = tck && count_en;

  reg [31:0] cmd;  // Address 4

  always @ (negedge tck or negedge rstn) begin
    if (rstn == 0)
      cmd[31:0] <= 32'b0;
    else if (write_register && address == 32'h4)
      cmd[31:0] <= data;
    else
      cmd[31:0] <= cmd[31:0];
  end

  // Read regs
  always @ (negedge tck) begin
    if (read_register && address == 32'b0)
      dr[31:0] <= ctrl[31:0];
    else if (read_register && address == 32'h4)
      dr[31:0] <= cmd[31:0];
    else if (read_register && address == 32'h8)
      dr[31:0] <= count[31:0];
    else
      dr[31:0] <= dr[31:0];
  end


endmodule
