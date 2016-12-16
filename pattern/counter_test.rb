Pattern.create do
  tester.set_timeset("func", 100)

  10000.times do
    tester.put("2%clock%1")
    tester.put("3%")
    tester.put("2%clock%1")
    tester.put("3%")
    tester.put("2%clock%1")
    tester.put("3%")
    tester.put("2%clock%1")
    tester.put("2%reset%1")
    tester.put("3%")
    tester.put("2%clock%1")
    tester.put("3%")
    tester.put("2%clock%1")
    tester.put("3%")
    tester.put("2%clock%1")
    tester.put("3%")
  end
end
