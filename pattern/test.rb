Pattern.create do
  tester.set_timeset("func", 100)

  tester.put("2%tck%1")
  tester.put("2%rstn%0")
  tester.put("2%trstn%1")
  tester.wait time_in_ms: 6
  tester.put("2%rstn%1")
  tester.wait time_in_ms: 1
end
