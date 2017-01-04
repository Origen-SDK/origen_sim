Pattern.create do
  tester.set_timeset("func", 100)

  dut.pin(:tck).drive(0)
  dut.pin(:tck).drive(1)
  dut.pin(:rstn).drive(0)
  dut.pin(:trstn).drive!(1)
  10.cycles
  dut.pin(:tdo).assert!(0)
  dut.pin(:tdo).assert!(1)
  dut.pin(:tdo).dont_care
  dut.pin(:rstn).drive(1)
  dut.jtag.write_ir(0x5, size: 4)
  tester.wait time_in_cycles: 10
end
