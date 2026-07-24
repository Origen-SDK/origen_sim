require 'origen_sim/origen/log'
module Origen
  class Log
    @orig_stop_job = instance_method(:stop_job)

    attr_accessor :skip_job_log_file_close

    def stop_job
      # Delay the per-job log closure until the simulator has finished shutting down,
      # otherwise the log file will be closed while the simulator is still running,
      # truncating anything from the simulator as well as pass/fail results
      unless skip_job_log_file_close
        self.class.instance_variable_get(:@orig_stop_job).bind(self).call
      end
    end
  end
end