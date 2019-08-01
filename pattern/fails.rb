# This pattern is expected to fail, use it to visually inspect that OrigenSim's
# error reporting is working
Pattern.create do
  ss "Test a register-level miscompare"
  dut.cmd.write!(0x1234_5678)
  dut.cmd.read!(0x1233_5678)

  ss "Test a register-level miscompare with named bits"
  dut.power_pin(:vdd).drive!(0)
  dut.ana_test.read!(1)

  ss "Test a bit-level miscompare, expect 1"
  dut.ana_test.write!(0)
  dut.ana_test.bgap_out.read!(1)
  ss "Test a bit-level miscompare, expect 0"
  dut.ana_test.bgap_out.write!(1)
  dut.ana_test.bgap_out.read!(0)

  if tester.sim?
    ss "Test reading an X register value, expect LSB nibble to be 0"
    dut.x_reg[3..0].read!(0)
  end

  ss "Test an out of bounds miscompare"
  dut.cmd.write!(0x1234_5678)
  dut.cmd.read!(0x1233_5678, force_out_of_bounds: true)

  ss "Test user out of bounds handler"
  if tester.sim?
    tester.out_of_bounds_handler = proc do |position, received, expected, reg|
      Origen.log.error "User handler hook is working --> #{reg.name}, bit[#{position}]: expected #{expected}, received #{received}"
    end
  end
  dut.cmd.read!(0x1233_5678, force_out_of_bounds: true)
end
