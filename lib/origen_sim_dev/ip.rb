module OrigenSimDev
  class IP
    include Origen::Model

    def initialize
      add_reg :dr, 0x0, size: 48 do |reg|
        reg.bits 47..32, :address
        reg.bits 31..0, :data
      end

      add_reg :cmd, 0x0
    end
  end
end
