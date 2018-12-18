Pattern.create do

  dut.ip2.cmd.write!(0x55)

  dut.ip2.cmd.read!
end
