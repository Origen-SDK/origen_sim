Pattern.create do
  IDCODE = 0b0010
  DEBUG  = 0b1000

  ss "Some basic shift operations to verify functionality"
  dut.jtag.write_ir(0x0, size: 4)
  dut.jtag.read_ir(0x0, size: 4)
  dut.jtag.write_ir(0xA, size: 4)
  dut.jtag.read_ir(0xA, size: 4)
  dut.jtag.write_ir(0xE, size: 4)
  dut.jtag.read_ir(0xE, size: 4)

  tester.set_timeset("func", 200)

  dut.jtag.write_ir(0x5, size: 4)
  dut.jtag.read_ir(0x5, size: 4)

  ss "Read the IDCODE value"
  dut.jtag.write_ir(IDCODE, size: 4)
  dut.jtag.read_dr(0x149511C3, size: 32)

  ss "Now try and shift in an out of the device DR"
  dut.jtag.write_ir(0x0, size: 4)
  dut.jtag.write_dr(0x1111_2222_3333_4444, size: 66)
  # Should not have been applied when not selected
  dut.jtag.read_dr(0, size: 66)

  dut.jtag.write_ir(DEBUG, size: 4)
  dut.jtag.write_dr(0x1111_2222_3333_4444, size: 66)
  dut.jtag.read_dr(0x1111_2222_3333_4444, size: 66)

  ss "Now try and read and write a register"
  dut.cmd.write!(0x1234_5678)
  dut.cmd.read!(0x1234_5678)

  tester.simulator.poke("dut.cmd", 0x1122_3344)
  dut.cmd.read!(0x1122_3344)

  ss "Do some operations with the counter, just for fun"
  dut.ctrl.write!(0b11) # Reset the counter
  dut.count.read!(0x0)
  dut.ctrl.write!(0b1)  # Start counting
  100.cycles
  dut.ctrl.write!(0b0)  # Stop counting
  dut.count.read!(0xAB)
end
