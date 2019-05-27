Pattern.sequence do |seq|
  1.cycle

  dut.ip1.communication_test

  seq.run :ip1_test

  seq.run :ip2_test

  seq.in_parallel :ip1 do
    seq.run :ip1_test
  end

  seq.in_parallel :ip2 do
    seq.run :ip2_test
  end
end
