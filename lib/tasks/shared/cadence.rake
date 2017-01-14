require 'open3'

tmp_dir = "#{Origen.root}/tmp/origen_sim/cadence"

directory tmp_dir
directory "#{tmp_dir}/pids"
directory "#{Origen.root}/waves"

c_source_files = Rake::FileList["#{Origen.root!}/ext/*.c", "#{Origen.root!}/ext/*.h"]
v_source_files = Rake::FileList["#{Origen.root}/spec/rtl_v/*.v"]

namespace :cadence do

  desc 'Deletes all compiled objects'
  task :clean do
    sh "rm -fr #{tmp_dir}"
  end

  desc 'Build the object containing the DUT and testbench'
  task build: [tmp_dir, "#{tmp_dir}/build_done"]

  file "#{tmp_dir}/build_done" => c_source_files + v_source_files do
    cd tmp_dir do
      sh "irun -incdir #{Origen.root}/spec/rtl_v #{Origen.root}/spec/rtl_v/origen_tb.v -timescale 1ns/1ns #{Origen.root!}/ext/*.c -ccargs \"-std=gnu99\" -elaborate -snapshot origen"
      sh "touch #{tmp_dir}/build_done"
    end
  end

  task :run, [:socket] => ["#{tmp_dir}/pids", "#{Origen.root}/waves", :build] do |t, args|
    #cd "#{Origen.root}/waves", verbose: false do
    cd tmp_dir, verbose: false do
      cmd = "irun -r origen -snapshot origen +socket+/tmp/#{args[:socket]}.sock & echo $!"

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
              puts line
            end
          end
        end
        threads.each(&:join)
      end
    end
  end

end
