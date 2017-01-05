Pattern.create do
  tester.set_timeset("func", 100)

  dut.pin(:rstn).drive!(1)
  10.cycles
  dut.pin(:tck).drive!(1)
  10.cycles
  dut.pin(:trstn).drive!(1)
  10.cycles
  dut.jtag.write_ir(0x5, size: 4)
  dut.jtag.read_ir(0x5, size: 4)
  dut.jtag.read_ir(0x5, size: 4)

  tester.set_timeset("func", 200)

  dut.jtag.write_ir(0x5, size: 4)
  dut.jtag.read_ir(0x5, size: 4)
end
