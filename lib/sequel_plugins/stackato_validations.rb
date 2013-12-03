
module Sequel::Plugins::StackatoValidations
  module InstanceMethods
    # Validates that an attribute is a valid application name
    #
    # @param [Symbol] The attribute to validate
    def validates_app_name(attr)
      validates_format(/^[a-zA-Z0-9\-]+$/, attr, :message => :app_name) if send(attr)
    end

  end
end

