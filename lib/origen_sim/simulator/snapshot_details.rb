require 'origen_sim/simulator/user_details'

module OrigenSim
  class Simulator
    # The SnapshotDetails and UserDetails share a lot in common, with the
    # SnapshotDetails containing a bit of extra stuff.
    class SnapshotDetails < UserDetails
      attr_reader :_user_details

      def initialize(simulator:, cache: true)
        # @fetch_error_message = "OrigenSim was unable to find net #{detail_names_net} in the snapshot! Unable to retrieve snapshot details!"
        super(simulator: simulator, cache: cache)

        @_user_details = UserDetails.new(simulator: simulator, cache: cache)
      end

      def detail_to_net(d)
        "#{@simulator.testbench_top}.debug.snapshot_details.#{d}"
      end

      def _missing_detail_message(d)
        "Detail '#{d}' is not an available snapshot detail name!"
      end

      ### The user details interface is the same as the snapshot_details ###
      ### just on the snapshot_details itself                            ###

      def user_details(d = nil)
        if d
          _user_details[d]
        else
          _user_details
        end
      end

      def user_detail(d)
        user_details(d)
      end
    end

    ### Add the following methods to the simulator ###

    def _snapshot_details
      @_snapshot_details ||= SnapshotDetails.new(simulator: self, **@configuration[:snapshot_details_options])
    end

    def snapshot_details(d = nil)
      if d
        _snapshot_details[d]
      else
        _snapshot_details
      end
    end

    def snapshot_detail(d)
      snapshot_details(d)
    end
  end
end
