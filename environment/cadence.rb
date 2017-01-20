OrigenSim::Tester.new vendor: :cadence,
                      irun: ENV["ORIGEN_SIM_IRUN"],
                      rtl_top: 'dut.v',
                      rtl_dir: "#{Origen.root}/spec/rtl_v",
                      rtl_files: "#{Origen.root}/spec/rtl_v/dut.v"
