module OrigenSimDev
  class IP
    include Origen::Model

    def initialize
      # Virtual reg to implement the JTAG scan chain
      add_reg :dr, 0x0, size: 49 do |reg|
        reg.bit 48, :write
        reg.bits 47..32, :address
        reg.bits 31..0, :data
      end

      # User regs
      add_reg :cmd, 0x0

      reg :status, 0x4 do |reg|
        reg.bit 2, :error, access: :w1c
        reg.bit 1, :fail, access: :w1c
        reg.bit 0, :busy
      end

      add_reg :data, 0x8
    end

    def communication_test
      ss "Communication test with #{name}"
      data.write!(0x1234)
      data.read!
      data.read!
      data.write!(0x5555_AAAA)
      data.read!
    end

    def execute_cmd(code)
      ss "Execute command #{code}"
      PatSeq.reserve :jtag do
        # This is redundant, but added as a test that if an embedded reservation is made to the same
        # resource then the end of the inner block does not release the reservation before completion
        # of the outer block
        PatSeq.reserve :jtag do
          # Verify that no command is currently running
          status.read!(0)
        end

        cmd.write!(code)
        10.cycles
        # Verify that the command has started

        status.busy.read!(1)
      end

      # Wait for the command to complete, a 'command' lasts for
      # 1000 cycles times the command code
      (code * 1000).cycles

      # Verify that the command completed and passed
      status.read!(0)
    end
  end
end
