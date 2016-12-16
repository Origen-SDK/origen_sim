module OrigenSim
  class Tester
    include OrigenTesters::VectorBasedTester

    def to_sim(msg)
      OrigenSim.simulator.socket.puts(msg)
    end

    # This method intercepts vector data from Origen, removes white spaces and compresses repeats
    def push_vector(options)
      programmed_data = options[:pin_vals].gsub(/\s+/, '')
      unless options[:timeset]
        puts 'No timeset defined!'
        puts 'Add one to your top level startup method or target like this:'
        puts '$tester.set_timeset("nvmbist", 40)   # Where 40 is the period in ns'
        exit 1
      end
      puts '*** Sending ***'
      to_sim('1:1')
      # tset = options[:timeset].name
      # if @vector_count > 0
      #  # compressing repeats as we go
      #  if (programmed_data == @previous_vectordata) && (@previous_tset == tset) && @store_pins.empty?
      #    @vector_repeatcount += 1
      #  else
      #    # all repeats of the previous vector have been counted
      #    # time to flush.  Don't panic though!  @previous_vectordata
      #    # is what gets flushed.  programmed_data is passed as an
      #    # arg to be set as the new @previous_vectordata
      #    flush_vector(programmed_data, tset)
      #  end
      # else
      #  # if this is the first vector of the pattern, insure variables are initialized
      #  @previous_vectordata = programmed_data
      #  @previous_tset = tset
      #  @vector_repeatcount = 1
      # end # if vector_count > 0
      # @vector_count += 1
    end
  end
end
