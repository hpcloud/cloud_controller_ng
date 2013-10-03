require "uaa/token_issuer"
require "uaa/scim"
require_relative 'stackato_user_creation'
module VCAP::CloudController
  rest_controller :StackatoUsers do
    include StackatoUserCreation
    path_base('stackato/users')

    do_define_attributes

    # def self.translate_validation_exception(e, attributes)
    #   guid_errors = e.errors.on(:guid)
    #   if guid_errors && guid_errors.include?(:unique)
    #     Errors::UaaIdTaken.new(attributes["guid"])
    #   else
    #     Errors::UserInvalid.new(e.errors.full_messages)
    #   end
    # end

    def create
      raise Errors::NotAuthenticated unless user
      raise Errors::NotAuthorized unless roles.admin?

      create_core
    end

    def enumerate
      raise Errors::NotAuthenticated unless user
      # TODO: stub, here to satisfy tests
      return {}.to_json
    end

    def read
      # TODO: implement or not
      raise "Not Implemented"
    end

    def update
      # TODO: implement or not
      raise "Not Implemented"
    end

    def delete
      # TODO: implement or not
      raise "Not Implemented"
    end

  end
end
