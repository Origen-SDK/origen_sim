Pattern.create do

  dut.ip1.cmd.write!(0x55)

  dut.ip1.cmd.read!
end
