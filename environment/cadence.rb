OrigenSim::Tester.new vendor: :cadence,
                      irun: ENV["ORIGEN_SIM_IRUN"],
                      simvision: ENV["ORIGEN_SIM_SIMVISION"],
                      setup: %Q(
                        probe -create -shm origen.dut -all -memories -variables -unpacked 262144 -depth all
                      )
