OrigenSim::Tester.new vendor: :icarus,
                      vvp: ENV["ORIGEN_SIM_VVP"]

OrigenSim.warning_string_exceptions << /array word origen.dut.(mem|wide_mem)\[\d+\] will conflict with an escaped identifier/
