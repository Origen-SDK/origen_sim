module OrigenSim
  module Generator
    extend ActiveSupport::Concern

    included do
      include OrigenTesters::Interface  # adds the interface helpers/Origen hook-up
    end

    def flow
      self
    end
  end
end
