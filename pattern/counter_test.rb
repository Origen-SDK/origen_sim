Pattern.create do
  #tester.set_timeset("func", 100)

  # Set period 100ns
  tester.to_sim("1%100")
  1.times do
    tester.to_sim("2%clock%1")
    tester.to_sim("3%")
    tester.to_sim("2%clock%0")
    tester.to_sim("3%")
    tester.to_sim("2%clock%1")
    tester.to_sim("3%")
    tester.to_sim("2%clock%0")
    tester.to_sim("3%")
    tester.to_sim("2%clock%1")
    tester.to_sim("3%")
    tester.to_sim("2%clock%0")
    tester.to_sim("3%")
    tester.to_sim("2%clock%1")
    tester.to_sim("2%reset%1")
    tester.to_sim("3%")
    tester.to_sim("2%clock%0")
    tester.to_sim("3%")
    tester.to_sim("2%clock%1")
    tester.to_sim("3%")
    tester.to_sim("2%clock%0")
    tester.to_sim("3%")
    tester.to_sim("2%clock%1")
    tester.to_sim("3%")
    tester.to_sim("2%clock%0")
    tester.to_sim("3%")
    tester.to_sim("2%clock%1")
    tester.to_sim("3%")
    tester.to_sim("2%clock%0")
    tester.to_sim("3%")
  end
  tester.to_sim("Z%")

  # Need to wait for ack here
  sleep 2
end
