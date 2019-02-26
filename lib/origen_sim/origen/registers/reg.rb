require 'origen/registers/reg'
module Origen
  module Registers
    # Override the Origen reg model so we can hook into into register read (and write) requests
    class Reg
      alias_method :orig_request, :request

      # Proxies requests from bit collections to the register owner
      def request(operation, options = {}) # :nodoc:
        if simulation_running? && operation == :read_register
          error_count = simulator.error_count
          pre_flight_check = named_bits.map do |name, bits|
            if bits.is_to_be_read?
              [name, bits.status_str(:read)]
            end
          end.compact
          orig_request(operation, options)
          if simulator.error_count > error_count
            Origen.log.error "Errors occurred reading register #{path}:"
            sync
            pre_flight_check.each do |name, expected|
              msg = "#{path}.#{name}: expected #{expected}"
              msg += " received #{bits(name).status_str(:write)}"
              Origen.log.error msg
            end
            Origen.log.error
            caller.each do |line|
              if Pathname.new(line.split(':').first).expand_path.to_s =~ /^#{Origen.root}(?!(\/lbin|\/vendor\/gems)).*$/
                Origen.log.error line
              end
            end
          end
        else
          orig_request(operation, options)
        end
      end

      def simulator
        tester.simulator
      end

      def simulation_running?
        tester && tester.is_a?(OrigenSim::Tester)
      end
    end
  end
end
