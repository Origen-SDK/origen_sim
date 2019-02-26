Pattern.create do
  IDCODE = 0b0010
  DEBUG  = 0b1000

  ss "Some basic shift operations to verify functionality"
  dut.jtag.write_ir(0x0, size: 4)
  dut.jtag.read_ir(0x0, size: 4)
  dut.jtag.write_ir(0xA, size: 4)
  dut.jtag.read_ir(0xA, size: 4)
  dut.jtag.write_ir(0xE, size: 4)
  dut.jtag.read_ir(0xE, size: 4)

  ss "Switch to slower timeset"
  ss "And test multiple comments for Github issue #8"
  ss "Blah blah, more stuff to verify that we can handle large comment blocks without having problems"
  ss "Blah blah, more stuff to verify that we can handle large comment blocks without having problems"
  tester.set_timeset("func", 200)

  dut.jtag.write_ir(0x5, size: 4)
  dut.jtag.read_ir(0x5, size: 4)

  ss "Read the IDCODE value"
  dut.jtag.write_ir(IDCODE, size: 4)
  dut.jtag.read_dr(0x149511C3, size: 32)

  ss "Now try and shift in an out of the device DR"
  dut.jtag.write_ir(0x0, size: 4)
  dut.jtag.write_dr(0x1111_2222_3333_4444, size: 66)
  # Should not have been applied when not selected
  dut.jtag.read_dr(0, size: 66)

  dut.jtag.write_ir(DEBUG, size: 4)
  dut.jtag.write_dr(0x1111_2222_3333_4444, size: 66)
  dut.jtag.read_dr(0x1111_2222_3333_4444, size: 66)

  ss "Now try and read and write a register"
  dut.cmd.write!(0x1234_5678)
  tester.marker = 1
  dut.cmd.read!(0x1234_5698)

  if tester.sim?
    tester.simulator.poke("dut.cmd", 0x1122_3344)
    dut.cmd.read!(0x1122_3344)
  end

  ss "Test storing a register"
  dut.cmd.write!(0x2244_6688)
  Origen.log.info "Should be within 'Test storing a register'"
  dut.cmd.store!

  if tester.sim?
    sim = tester.simulator
    capture_value = sim.peek("origen.pins.tdo.memory").to_i[31..0]
    unless capture_value == 0x11662244 # 0x2244_6688 reversed
      if capture_value
        OrigenSim.error "Captured #{capture_value.to_hex} instead of 0x11662244!"
      else
        OrigenSim.error "Nothing captured instead of 0x11662244!"
      end
    end

    ss "Test sync of a register"
    dut.cmd.write(0) # Make Origen forget the actual value
    dut.cmd.sync
    unless dut.cmd.data == 0x2244_6688
      OrigenSim.error "CMD register did not sync from simulation"
    end

    ss "Test sync of a register via a parallel interface"
    dut.parallel_read.write(0)
    dut.data_out.write!(0x7707_7077)
    dut.pins(:dout).assert!(0x7707_7077)
    dut.pins(:dout).dont_care
    dut.parallel_read.sync
    unless dut.parallel_read.data == 0x7707_7077
      OrigenSim.error "PARALLEL_READ register did not sync from simulation"
    end
  end

  ss "Do some operations with the counter, just for fun"
  dut.ctrl.write!(0b11) # Reset the counter
  dut.count.read!(0x0)
  dut.ctrl.write!(0b1)  # Start counting
  100.cycles
  dut.ctrl.write!(0b0)  # Stop counting
  dut.count.read!(0xAB)

  ss "Verify that pin group read/write works"
  dut.pins(:din_port).drive!(0x1234_5678)
  dut.data_in.read!(0x1234_5678)

  dut.data_out.write!(0)
  dut.pins(:dout).assert!(0)
  dut.pins(:dout).dont_care
  dut.data_out.write!(0x5555_AAAA)
  dut.pins(:dout).assert!(0x5555_AAAA)
  dut.pins(:dout).dont_care

  ss "Verify that forcing pins works"
  dut.p.p1.assert!(0)
  dut.p.p2.assert!(1)
  dut.p.p3.assert!(0)
  dut.p.p4.assert!(0xA)

  ss "Test sim_capture"
  tester.sim_capture :cmd55, :dout, :test_bus, :tdo do
    dut.pins(:din_port).drive!(0x1234_5678)
    dut.cmd.write!(0x55)
    60.cycles
  end

  ss "Test the command works with static vectors"
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care
  dut.cmd.write!(0x75)
  5.cycles
  dut.pin(:done).assert!(0)
  dut.pin(:done).dont_care
  500.cycles
  dut.pin(:done).assert!(0)
  dut.pin(:done).dont_care
  500.cycles
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care

  ss "Test basic match loop"
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care
  dut.cmd.write!(0x75)
  5.cycles
  dut.pin(:done).assert!(0)
  dut.pin(:done).dont_care
  tester.wait match: true, time_in_cycles: 2000, pin: dut.pin(:done), state: :high
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care

  ss "Test basic 2-pin match loop"
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care
  dut.cmd.write!(0x75)
  5.cycles
  dut.pin(:done).assert!(0)
  dut.pin(:done).dont_care
  tester.wait match: true, time_in_cycles: 2000, pin: dut.pin(:tdo), state: :low,
                                                 pin2: dut.pin(:done), state2: :high
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care

  ss "Test a block match loop"
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care
  dut.cmd.write!(0x75)
  5.cycles
  dut.pin(:done).assert!(0)
  dut.pin(:done).dont_care
  tester.wait match: true, time_in_cycles: 2000 do
    dut.pin(:done).assert!(1)
  end
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care

#  ss "Test a multi-block match loop"
#  dut.pin(:done).assert!(1)
#  dut.pin(:done).dont_care
#  dut.cmd.write!(0x75)
#  dut.pin(:done).assert!(0)
#  dut.pin(:done).dont_care
#  tester.wait match: true, time_in_cycles: 2000 do |conditions, fail|
#    # Just do two conditions that do the same thing here, the content
#    # is not important for testing this feature
#    conditions.add do
#      dut.pin(:done).assert!(1)
#    end
#    conditions.add do
#      dut.pin(:done).assert!(1)
#    end
#  end
#  dut.pin(:done).assert!(0)
#  dut.pin(:done).dont_care

  ss "Test sim_delay"
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care
  dut.cmd.write!(0x75)
  5.cycles
  dut.pin(:done).assert!(0)
  dut.pin(:done).dont_care
  tester.sim_delay :delay1 do
    dut.pin(:done).assert!(1)
  end
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care

  ss "Test sim delay with timeout"
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care
  dut.cmd.write!(0x75)
  5.cycles
  dut.pin(:done).assert!(0)
  dut.pin(:done).dont_care
  tester.sim_delay :delay1, time_in_cycles: 2000 do
    dut.pin(:done).assert!(1)
  end
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care

  ss "Test sim delay with resolution"
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care
  e = tester.cycle_count
  dut.cmd.write!(0x75)
  5.cycles
  dut.pin(:done).assert!(0)
  dut.pin(:done).dont_care
  tester.sim_delay :delay1, resolution: 10 do
    dut.pin(:done).assert!(1)
  end
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care

  ss "Test sim delay with resolution and timeout"
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care
  e = tester.cycle_count
  dut.cmd.write!(0x75)
  5.cycles
  dut.pin(:done).assert!(0)
  dut.pin(:done).dont_care
  tester.sim_delay :delay1, time_in_cycles: 2000, resolution: { time_in_cycles: 10 } do
    dut.pin(:done).assert!(1)
  end
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care

  ss "Test sim delay with padding"
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care
  e = tester.cycle_count
  dut.cmd.write!(0x75)
  5.cycles
  dut.pin(:done).assert!(0)
  dut.pin(:done).dont_care
  tester.sim_delay :delay1, time_in_cycles: 2000, padding: { time_in_cycles: 500 } do
    dut.pin(:done).assert!(1)
  end
  dut.pin(:done).assert!(1)
  dut.pin(:done).dont_care
  if (tester.cycle_count - e) < 1400
    OrigenSim.error "sim_delay padding was not applied!"
  end
end
