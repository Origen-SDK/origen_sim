OrigenSim::Tester.new vendor: :icarus,
                      vvp: ENV["ORIGEN_SIM_VVP"],
                      rtl_top: 'dut.v',
                      rtl_dir: "#{Origen.root}/spec/rtl_v",
                      rtl_files: "#{Origen.root}/spec/rtl_v/dut.v"
