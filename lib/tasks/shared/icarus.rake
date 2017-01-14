require 'open3'

tmp_dir = "#{Origen.root}/tmp/origen_sim/icarus"

directory tmp_dir
directory "#{tmp_dir}/pids"
directory "#{Origen.root}/waves"

c_source_files = Rake::FileList["#{Origen.root!}/ext/*.c"]
source_files = Rake::FileList["#{Origen.root!}/ext/*.c", "#{Origen.root!}/ext/*.h"]

namespace :icarus do

  desc 'Compiles the VPI extension'
  task compile: [tmp_dir, "#{tmp_dir}/origen.vpi"]

  file "#{tmp_dir}/origen.vpi" => source_files do
    cd tmp_dir do
      sh "iverilog-vpi #{c_source_files} -DICARUS --name=origen"
    end
  end

  desc 'Deletes all compiled objects'
  task :clean do
    sh "rm -fr #{tmp_dir}"
  end

  desc 'Build the object containing the DUT and testbench'
  task build: [:compile, "#{tmp_dir}/dut.vvp"]

  v_source_files = Rake::FileList["#{Origen.root}/spec/rtl_v/*.v"]

  file "#{tmp_dir}/dut.vvp" => v_source_files do
    cd tmp_dir do
      sh "iverilog -o dut.vvp -I #{Origen.root}/spec/rtl_v #{Origen.root}/spec/rtl_v/origen_tb.v"
    end
  end

  task :run, [:socket] => ["#{tmp_dir}/pids", "#{Origen.root}/waves", :build] do |t, args|
    cd "#{Origen.root}/waves", verbose: false do
      cmd = "vvp -M#{tmp_dir} -morigen #{tmp_dir}/dut.vvp -socket /tmp/#{args[:socket]}.sock & echo $!"

      Open3.popen3(cmd) do |stdin, stdout, stderr, thread|
        pid = stdout.gets.strip
        File.open "#{tmp_dir}/pids/#{args[:socket]}", 'w' do |f|
          f.puts pid
        end
        threads = []
        [stdout, stderr].each do |stream|
          threads << Thread.new do
            until (line = stream.gets).nil?
              # Not sure if we want to hear directly from the simulator
              # puts line
            end
          end
        end
        threads.each(&:join)
      end
    end
  end

end
