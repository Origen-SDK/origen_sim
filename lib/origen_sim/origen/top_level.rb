require 'origen/top_level'
module Origen
  module TopLevel
    # Like pins, except removes any pins which have their rtl_name
    # attribute set to 'nc'
    def rtl_pins
      @rtl_pins ||= begin
        p = []
        pins.each do |name, pin|
          options = {}
          unless pin.rtl_name.to_s.downcase == 'nc'
            if pin.primary_group
              options[:group] = true
            end
            p << [name, pin, options]
          end
        end
        p
      end
    end
  end
end
