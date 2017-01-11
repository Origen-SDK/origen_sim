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
  end
end
