require 'cloud_controller/security/security_context_configurer'

module VCAP::CloudController
  include VCAP::RestAPI

  Errors = VCAP::Errors

  class Controller < Sinatra::Base
    register Sinatra::VCAP

    attr_reader :config

    vcap_configure(logger_name: "cc.api", reload_path: File.dirname(__FILE__))

    def initialize(config, token_decoder)
      @config = config
      @token_decoder = token_decoder
      super()
    end

    before do
      VCAP::CloudController::SecurityContext.clear
      auth_token = env["HTTP_AUTHORIZATION"]

      VCAP::CloudController::Security::SecurityContextConfigurer.new(@token_decoder).configure(auth_token)

      token_information = VCAP::CloudController::SecurityContext.token
      token_information = nil if token_information == :invalid_token
      if token_information
        token_information['user_id'] ||= token_information['client_id']
        uaa_id = token_information['user_id']
      else
        uaa_id = nil
      end

      if uaa_id
        user = User.find(:guid => uaa_id.to_s)
        if user.nil?
          User.db.transaction do
            user = User.create(guid: token_information['user_id'], admin: current_user_admin?(token_information), active: true)
            # The old code updated SecurityContext.user
            VCAP::CloudController::SecurityContext.set(user, token_information)
            default_org = Organization.where(:is_default => true).first
            if default_org
              default_org.add_user(user)
              default_space = Space.where(:is_default => true).first
              if default_space
                default_space.add_developer(user)
              end
            end
          end
        end
      end
      
      validate_scheme
    end

    get "/hello/sync" do
      "sync return\n"
    end

    private

    def validate_scheme
      user = VCAP::CloudController::SecurityContext.current_user
      admin = VCAP::CloudController::SecurityContext.admin?
      return unless user || admin

      if @config[:https_required]
        raise Errors::ApiError.new_from_details("NotAuthorized") unless request.scheme == "https"
      end

      if @config[:https_required_for_admins] && admin
        raise Errors::ApiError.new_from_details("NotAuthorized") unless request.scheme == "https"
      end
    end
  end
end
