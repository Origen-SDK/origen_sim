require 'origen/top_level'
module Origen
  module TopLevel
    # Like pins, except removes any pins which have their rtl_name
    # attribute set to 'nc'
    # Optionally pass in a type: option set to either :analog or :digital to
    # have only the pins with that type returned
    def rtl_pins(options = {})
      _add_rtl_pin_ = lambda do |name, pin, opts, p|
        options = {}
        unless pin.rtl_name.to_s.downcase == 'nc' ||
               (opts[:type] && pin.type && opts[:type] != pin.type) ||
               (pin.meta[:origen_sim_init_pin_state] && pin.meta[:origen_sim_init_pin_state] == -2)
          if pin.primary_group
            options[:group] = true
          end
          p << [name, pin, options]
        end
      end

      pin_roles = [:pins, :power_pins, :ground_pins, :virtual_pins, :other_pins]
      @rtl_pins ||= {}
      @rtl_pins[options[:type]] ||= begin
        opts = options.dup
        p = []
        # pins.each do |name, pin|
        pin_roles.each do |role|
          dut.send(role).each do |name, pin|
            _add_rtl_pin_.call(name, pin, opts, p)
          end
        end
        p
      end
    end
  end
end
