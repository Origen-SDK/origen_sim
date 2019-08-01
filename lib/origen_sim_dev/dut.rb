module OrigenSimDev
  class DUT
    include Origen::TopLevel
    include OrigenJTAG

    JTAG_CONFIG = {
      tclk_format: :rl
    }

    def initialize(options = {})
      add_pin :tck, reset: :drive_lo
      add_pin :tdi, reset: :drive_lo
      add_pin :tdo
      add_pin :tms, reset: :drive_lo
      add_pin :rstn, reset: :drive_lo
      add_pin :trstn, reset: :drive_lo
      add_pin_alias :tclk, :tck
      add_pin :dout, size: 32
      add_pin :test_bus, size: 16
      add_pin :din_port, size: 32, rtl_name: 'din', reset: :drive_lo
      add_pin :p1, force: 0
      add_pin :p2, force: 1
      add_pin :p3, size: 4, force: 0
      add_pin :p4, size: 4, force: 0xA
      add_pin :v1, rtl_name: 'nc'
      add_pin :v2, rtl_name: :nc
      add_pin :done
      add_pin :not_present
      add_power_pin :vdd
      add_pin :ana, type: :analog

      timeset :func do |t|
        # Generate a clock pulse on TCK
        t.wave :tck do |w|
          w.drive 0, at: 0
          w.drive :data, at: 'period / 2'
        end
      end

      add_reg :dr, 0x0, size: 66 do |reg|
        reg.bit 65, :rg_enable
        reg.bit 64, :rg_read
        reg.bits 63..32, :rg_addr
        reg.bits 31..0, :rg_data
      end

      add_reg :ctrl, 0x0 do |reg|
        reg.bit 0, :rg_enable
        reg.bit 1, :rg_reset
      end

      add_reg :cmd, 0x4

      add_reg :count, 0x8

      add_reg :data_out, 0xC

      add_reg :data_in, 0x10

      add_reg :p, 0x14 do |reg|
        reg.bits 0, :p1
        reg.bits 1, :p2
        reg.bits 5..2, :p3
        reg.bits 9..6, :p4
      end

      # Reg for testing parallel read/sync when this one is read the data will
      # be read out via dout rather than JTAG
      add_reg :parallel_read, 0x18 do |reg|
        reg.bits 30..28, :b1
        reg.bits 26..24, :b2
        reg.bits 18..16, :b3
        reg.bits 14..12, :b4
        reg.bits 6..4, :b5
        reg.bits 2..0, :b6
      end

      add_reg :ana_test, 0x1C do |reg|
        reg.bit 0, :vdd_valid, access: :ro
        reg.bit 1, :bgap_out
        reg.bit 2, :osc_out
        reg.bit 3, :vdd_div4
      end

      add_reg :x_reg, 0x20

      sub_block :ip1, class_name: 'IP'
      sub_block :ip2, class_name: 'IP'
    end

    def interactive_startup
      if tester.sim?
        tester.start
        startup
      end
    end

    def simulation_startup
      power_pin(:vdd).drive(0)
    end

    def startup(options = {})
      # tester.simulator.log_messages = true
      tester.set_timeset('func', 100)

      dut.pin(:rstn).drive!(1)
      10.cycles
      dut.pin(:rstn).drive!(0)
      10.cycles
      dut.pin(:rstn).drive!(1)
      10.cycles
      dut.pin(:tck).drive!(1)
      10.cycles
      dut.pin(:trstn).drive!(1)
      10.cycles
    end

    def write_register(reg, options = {})
      PatSeq.serialize :jtag do
        if reg.path =~ /ip(\d)/
          ir_val = 0b0100 | Regexp.last_match(1).to_i
          jtag.write_ir(ir_val, size: 4)
          ip = reg.parent
          ip.dr.bits(:write).write(1)
          ip.dr.bits(:address).write(reg.address)
          ip.dr.bits(:data).write(reg.data)
          jtag.write_dr(ip.dr)
        # Write to top-level reg
        else
          jtag.write_ir(0x8, size: 4)
          dr.rg_enable.write(1)
          dr.rg_read.write(0)
          dr.rg_addr.write(reg.address)
          dr.rg_data.write(reg.data)
          jtag.write_dr(dr)
        end
      end
    end

    def read_register(reg, options = {})
      PatSeq.serialize :jtag do
        tester.read_register(reg, options) do
          # Special read for this register to test sync'ing over a parallel port
          if reg.id == :parallel_read
            pins = []
            reg.shift_out_with_index do |bit, i|
              if bit.is_to_be_stored?
                pins << dut.pins(:dout)[i]
              end
            end
            tester.store_next_cycle(*pins.reverse)
            1.cycle
            dut.pins(:dout).dont_care
          else
            if reg.path =~ /ip(\d)/
              ir_val = 0b0100 | Regexp.last_match(1).to_i
              jtag.write_ir(ir_val, size: 4)
              ip = reg.parent
              ip.dr.bits(:write).write(0)
              ip.dr.bits(:address).write(reg.address)
              ip.dr.bits(:data).write(0)
              jtag.write_dr(ip.dr)
              ip.dr.bits(:data).copy_all(reg)
              jtag.read_dr(ip.dr)
            else
              jtag.write_ir(0x8, size: 4)
              dr.rg_enable.write(1)
              dr.rg_read.write(1)
              dr.rg_addr.write(reg.address)
              jtag.write_dr(dr)
              dr.rg_enable.write(0)
              dr.rg_data.copy_all(reg)
              if !options[:force_out_of_bounds]
                jtag.read_dr(dr)
              else
                expect_val = dr.data + 2**dr.size
                jtag.read_dr expect_val, size: dr.size + 1
              end
            end
          end
        end
        reg.clear_flags
      end
    end
  end
end
