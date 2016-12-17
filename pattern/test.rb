Pattern.create do
  tester.set_timeset("func", 100)

  dut.pin(:tck).drive(1)
  dut.pin(:rstn).drive(0)
  dut.pin(:trstn).drive!(1)
  10.cycles
  dut.jtag.write_ir(0x5, size: 4)
  tester.wait time_in_ns: 500
end
