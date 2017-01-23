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
    end

    def interactive_startup
      if tester.sim?
        tester.start
        startup
      end
    end

    def startup(options = {})
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
