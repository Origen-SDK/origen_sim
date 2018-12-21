Pattern.create do

  dut.ip2.communication_test

  dut.ip2.execute_cmd(10)
  dut.ip2.execute_cmd(10)
  dut.ip2.execute_cmd(10)
end
