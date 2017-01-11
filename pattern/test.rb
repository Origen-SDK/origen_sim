Pattern.create do
  dut.jtag.write_ir(0x0, size: 4)
  dut.jtag.read_ir(0x0, size: 4)
  dut.jtag.write_ir(0x8, size: 4)
  dut.jtag.read_ir(0x8, size: 4)
  dut.jtag.write_ir(0xA, size: 4)
  dut.jtag.read_ir(0xA, size: 4)
  dut.jtag.write_ir(0xE, size: 4)
  dut.jtag.read_ir(0xE, size: 4)

  tester.set_timeset("func", 200)

  dut.jtag.write_ir(0x5, size: 4)
  dut.jtag.read_ir(0x5, size: 4)
end
