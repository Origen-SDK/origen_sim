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
    end

    def interactive_startup
      if tester.sim?
        tester.start
        startup
      end
    end

    def startup(options = {})
      # tester.simulator.log_messages = true
      tester.set_timeset('func', 100)

      dut.pin(:rstn).drive!(1)
      10.cycles
      dut.pin(:tck).drive!(1)
      10.cycles
      dut.pin(:trstn).drive!(1)
      10.cycles
    end

    def write_register(reg, options = {})
      jtag.write_ir(0x8, size: 4)
      dr.rg_enable.write(1)
      dr.rg_read.write(0)
      dr.rg_addr.write(reg.address)
      dr.rg_data.write(reg.data)
      jtag.write_dr(dr)
    end

    def read_register(reg, options = {})
      jtag.write_ir(0x8, size: 4)
      dr.rg_enable.write(1)
      dr.rg_read.write(1)
      dr.rg_addr.write(reg.address)
      jtag.write_dr(dr)
      dr.rg_enable.write(0)
      dr.rg_data.copy_all(reg)
      jtag.read_dr(dr)
    end
  end
end
