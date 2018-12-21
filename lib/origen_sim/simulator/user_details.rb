module OrigenSim
  class Simulator
    class UserDetails
      DETAIL_NAMES_NET = '_AVAILABLE_DETAILS_'

      attr_reader :cache
      attr_reader :details

      def initialize(simulator:, cache: true)
        @simulator = simulator
        @fetch_error_message = "OrigenSim was unable to find net #{detail_names_net} in the snapshot! Unable to retrieve snapshot details!"
        @details = fetch
        @cache = cache
      end

      # This gets called for some reason when 'puts' is used for the object.
      # Provide something here to avoid seeing the error message.
      def to_ary
        nil
      end

      def method_missing(method, *args, &block)
        self[method]
      end

      def [](d)
        _d = d.to_s.upcase
        if cache
          if details
            if details.key?(_d)
              details[_d]
            else
              Origen.log.error(_missing_detail_message(_d))
              nil
            end
          else
            # if detail fetching failed, but the user is still trying to query
            # details, re-print the fetch error message
            Origen.log.error(@fetch_error_message)
            nil
          end
        else
          details = fetch
          if details
            if details.key?(_d)
              details[_d]
            else
              Origen.log.error(_missing_detail_message(_d))
              nil
            end
          end
        end
      end

      def _missing_detail_message(d)
        "Detail '#{d}' was not provided in this snapshot!"
      end

      # Fetches the details available in the snapshot.
      #   This is done at runtime to get the latest details list from the snapshot
      #   but can be cached for future use.
      # @note This requires the details <code>origen.debug.AVAILABLE_DETAILS</code>
      #  to be defined. This should be a comma-separeted string of the available values.
      #  It will be assumed that each details will be defined in the snapshot.
      def fetch
        puts 'FETCHING!'.cyan
        # Read the available details.
        # names = str_peek("#{debug_module}.PARAMETER_NAMES").split(',')
        names = @simulator.peek_str(detail_names_net)
        if names.nil?
          Origen.log.error(@fetch_error_message)

          # Returning false indicates that the fetch failed.
          false
        elsif names.empty?
          # Empty string was returned. No available details/no details given.
          {}
        else
          # Fetch each detail value and return as a Hash
          names.split(',').map do |n|
            [n, @simulator.str_peek(detail_to_net(n))]
          end.to_h
        end
      end

      def available_details
        if details
          details.keys
        else
          details = fetch
          @details = details if cache
          if details
            details.keys
          end
        end
      end

      def detail_to_net(d)
        "#{@simulator.testbench_top}.debug.snapshot_details.user_details.#{d}"
      end

      def detail_names_net
        detail_to_net(DETAIL_NAMES_NET)
      end
    end
  end
end
