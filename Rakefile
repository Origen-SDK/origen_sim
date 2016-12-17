# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/origen_sim.rake, and they will automatically
# be available to Rake.
#
# Any task files found in lib/tasks/shared/*.rake will be made available to 3rd party
# apps that use this plugin
require "bundler/setup"
require "origen"
require "rbconfig"

Origen.app.load_tasks

Simulator = Struct.new(:id, :name, :compiler_args, :linker_args)

SIMULATORS = [
#  Simulator.new(:cver,  'GPL Cver',        '-DCVER',  ''),
  Simulator.new(:ivl,   'Icarus Verilog',  '-DICARUS',  ''),
#  Simulator.new(:ncsim, 'Cadence NC-Sim',  '-DNCSIM',   ''),
#  Simulator.new(:vcs,   'Synopsys VCS',    '-DVCS',    ''),
#  Simulator.new(:vsim,  'Mentor Modelsim', '-DMODELSIM', ''),
]

tmp_dir = "#{Origen.root}/tmp/origen_sim_#{RbConfig::CONFIG["arch"]}"

namespace "sim" do

  directory tmp_dir
  directory "#{Origen.root}/waves"

  task :environment do
    Origen.load_target
  end

  desc "Compiles the VPI extension"
  task :compile => [tmp_dir, "#{tmp_dir}/origen.vpi"]

  c_source_files = Rake::FileList["#{Origen.root!}/ext/*.c"]
  source_files = Rake::FileList["#{Origen.root!}/ext/*.c", "#{Origen.root!}/ext/*.h"]

  file "#{tmp_dir}/origen.vpi" => source_files do
    cd tmp_dir do
      sh "iverilog-vpi #{c_source_files} -DICARUS --name=origen"
    end
  end

  desc "Deletes all compiled objects"
  task :clean do
    sh "rm -fr #{tmp_dir}"
  end

  desc "Build the object containing the DUT and testbench"
  task :build => [:compile, "#{tmp_dir}/dut.vvp"]

  v_source_files = Rake::FileList["#{Origen.root}/spec/rtl_v/*.v"]

  file "#{tmp_dir}/dut.vvp" => v_source_files do
    cd tmp_dir do
      sh "iverilog -o dut.vvp -I #{Origen.root}/spec/rtl_v #{Origen.root}/spec/rtl_v/dut_tb.v"
    end
  end

  task :run, [:socket] => ["#{Origen.root}/waves", :build] do |t, args|
    cd "#{Origen.root}/waves" do
      sh "vvp -M#{tmp_dir} -morigen #{tmp_dir}/dut.vvp -socket #{args[:socket]}"
    end
  end

end
