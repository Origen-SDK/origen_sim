Pattern.create do

  dut.ip1.communication_test

  dut.ip1.execute_cmd(1)

  dut.ip1.execute_cmd(50)

end
