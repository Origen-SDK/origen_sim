module OrigenSim
  class Flow
    include OrigenTesters::Flow

    def test(name, options = {})
      pattern = (name || options[:pattern] || name.try(:pattern)).to_s

      Origen.interface.referenced_patterns << pattern

      Origen.app.runner.launch action: :generate, files: pattern
    end
  end
end
