module OrigenSim
  module Commands
    module Pack
      # Note, making this a module instead of straight code so it can be called
      # programatically to auto-unpack a snapshot.

      def self.pack(options = {})
        testbench = "#{Origen.app.root}/simulation"
        unless Dir.exist?(testbench)
          fail "Could not find path #{testbench}/#{ARGV[0]}"
        end

        FileUtils.mkdir("#{Origen.app.root}/simulation/static") unless Dir.exist?("#{Origen.app.root}/simulation/static")

        output = "#{Origen.app.root}/simulation/static/#{ARGV[0]}.tar.gz"
        puts "Packing #{testbench} into #{output}..."
        system "tar vczf #{output} -C #{testbench} #{Origen.target.name}"
      end

      def self.unpack(options = {})
        testbench = "#{Origen.app.root}/simulation/static/#{ARGV[0]}.tar.gz"
        unless File.exist?(testbench)
          fail "Could not find #{testbench}"
        end

        output = "#{Origen.app.root}/simulation"
        FileUtils.mkdir(output) unless Dir.exist?(output)

        puts "Unpakcing Testbench into #{output}"
        system "tar vxzf #{testbench} -C #{output} #{ARGV[0]}"
      end

      def self.list(options = {})
      end
    end
  end
end
