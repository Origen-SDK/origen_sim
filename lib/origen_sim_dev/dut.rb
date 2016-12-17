module OrigenSimDev
  class DUT
    include Origen::TopLevel
    include OrigenJTAG

    JTAG_CONFIG = {
      tclk_format: :rl
    }

    def initialize(options = {})
      add_pin :tck
      add_pin :tdi
      add_pin :tdo
      add_pin :tms
      add_pin :rstn
      add_pin :trstn
      add_pin_alias :tclk, :tck
    end
  end
end
