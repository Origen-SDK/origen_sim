require 'origen_sim/flow'
module OrigenSim
  module Generator
    extend ActiveSupport::Concern

    included do
      include OrigenTesters::Interface  # adds the interface helpers/Origen hook-up
    end

    def flow(filename = nil)
      if filename || Origen.file_handler.current_file
        filename ||= Origen.file_handler.current_file.basename('.rb').to_s
        # DH here need to reset the flow!!
        f = filename.to_sym
        return flow_sheets[f] if flow_sheets[f] # will return flow if already existing
        p = OrigenSim::Flow.new
        p.inhibit_output if Origen.interface.resources_mode?
        p.filename = f
        flow_sheets[f] = p
      end
    end

    def test(name, options = {})
      flow.test(name, options)
    end

    def flow_sheets
      @@flow_sheets ||= {}
    end

    def reset_globals
      @@flow_sheets = nil
    end

    def sheet_generators
      []
    end
  end
end
