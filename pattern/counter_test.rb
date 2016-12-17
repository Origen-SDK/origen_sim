Pattern.create do
  tester.set_timeset("func", 100)

  tester.put("2%clock%1")
  tester.put("3%1")
  tester.put("3%10000")
  tester.put("3%1")
  tester.put("2%reset%1")
  tester.put("3%1")
  tester.put("3%1")
  tester.put("3%1")
  tester.put("3%1")
end
