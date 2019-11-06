Pattern.create do
  IDCODE = 0b0010
  DEBUG  = 0b1000

  # Peeks the given net and will fail if the returned value does not equal the expected
  def peek(net, expected)
    if expected.is_a?(Integer)
      actual = tester.peek(net)
    else
      actual = tester.peek_real(net)
    end
    if actual
      if expected.is_a?(Integer)
        actual = actual.to_i
        actual_str = actual.try(:to_hex) || 'nil'
        expected_str = expected.to_hex
      else
        actual_str = actual ? actual.to_s : 'nil'
        expected_str = expected.to_s
      end
      unless actual == expected
        OrigenSim.error "Expected to peek #{expected_str} from #{net}, got #{actual_str}!"
      end
    else
      OrigenSim.error "Nothing returned from peek of #{net}!"
    end
  end

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
  dut.cmd.read!(0x1234_5678)

  if tester.sim?
    ss "Test poking a register value"
    tester.simulator.poke("dut.cmd", 0x1122_3344)
    dut.cmd.read!(0x1122_3344)

    ss "Test peeking a register value"
    peek("dut.cmd", 0x1122_3344)

    ss "Test forcing a value"
    tester.force("dut.cmd", 0x2222_3333)
    dut.cmd.read!(0x2222_3333)
    peek("dut.cmd", 0x2222_3333)
    dut.cmd.write!(0x1234_5678)
    dut.cmd.read!(0x2222_3333)

    ss "Test releasing a forced value"
    tester.release("dut.cmd")
    dut.cmd.write!(0x1234_5678)
    dut.cmd.read!(0x1234_5678)

    ss "Test poking a real value"
    tester.poke("dut.real_val", 1.25)
    10.cycles

    ss "Verify that the memory can be accessed"
    dut.mem(0x1000_0000).write!(0x1234_5678)
    dut.mem(0x1000_0000).read!(0x1234_5678)

    ss "Test poking a memory"
    tester.poke("dut.mem[1]", 0x1111_2222)
    dut.mem(0x1000_0004).read!(0x1111_2222)

    ss "Test peeking a memory"
    tester.poke("dut.mem[2]", 0x1111_2222)
    peek("dut.mem[2]", 0x1111_2222)

    ss "Test peeking and poking a wide memory"
    tester.poke("dut.wide_mem[2]", 0x1FF_1111_2222_3333_4444_5555_6666_7777_8888)
    peek("dut.wide_mem[2]", 0x1FF_1111_2222_3333_4444_5555_6666_7777_8888)

    # Peek (or force?) a real value not working on Icarus, can't get it to work but not
    # spending much time on it since this is mainly useful in a WREAL simulation and other
    # things don't work that are blocking that anyway
    unless tester.simulator.config[:vendor] == :icarus
      ss "Test peeking a real value"
      peek("dut.real_val", 1.25)
      10.cycles

      ss "Test forcing a real value"
      tester.force("dut.real_val", 2.25)
      10.cycles
      peek("dut.real_val", 2.25)

      ss "Test releasing a forced real value"
      tester.poke("dut.real_val", 1.25)
      10.cycles
      peek("dut.real_val", 2.25)
      tester.release("dut.real_val")
      10.cycles
      peek("dut.real_val", 2.25)
      tester.poke("dut.real_val", 1.25)
      10.cycles
      peek("dut.real_val", 1.25)
    end

    if tester.simulator.wreal?
      ss "Test analog pin API by ramping dut.vdd"
      v = 0
      dut.power_pin(:vdd).drive!(v)
      dut.ana_test.vdd_valid.read!(0)
      until v >= 1.25
        v += 0.05
        dut.power_pin(:vdd).drive!(v)
      end
      dut.ana_test.vdd_valid.read!(1)
      100.cycles

      ss "Test analog pin measure API"
      dut.ana_test.vdd_div4.write!(1)
      measured = dut.pin(:ana).measure
      if measured != 0.3125
        OrigenSim.error "Expected to measure 0.3125V from the ana pin, got #{measured}V!"
      end

      ss "Test the different analog mux functions"
      dut.ana_test.write(0)
      dut.ana_test.vdd_div4.write!(1)
      1000.cycles
      dut.ana_test.write(0)
      dut.ana_test.bgap_out.write!(1)
      1000.cycles
      dut.ana_test.write(0)
      dut.ana_test.osc_out.write!(1)
      1000.cycles
    end
  end

  ss "Test storing a register"
  dut.cmd.write!(0x2244_6688)
  Origen.log.info "Should be within 'Test storing a register'"
  dut.cmd.store!
  if tester.sim?
    peek("origen.pins.tdo.memory", 0x11662244) # 0x2244_6688 reversed
  end

  if tester.sim?
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

  ss "Test timing implementation - drive timing, single data event only, not at t0"
  dut.pins(:din_port).dont_care
  tester.cycle
  dut.pins(:din_port).drive! 1
  dut.pins(:din_port).drive! 0
  dut.pins(:din_port).drive! 1

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
  
  Origen.log.info("Testing that OrigenSim can send exceedingly long messages through the simulator...")
  Origen.log.debug('OrigenSim'*1024)
  Origen.log.success("If you see this, it worked!")
end
