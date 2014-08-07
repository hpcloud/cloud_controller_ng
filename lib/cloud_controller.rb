require "bcrypt"
require "sinatra"
require "sequel"
require "thin"
require "yajl"
require "delayed_job"

require "allowy"

require "eventmachine/schedule_sync"

require "vcap/common"
require "vcap/errors"
require "uaa/token_coder"

require "sinatra/vcap"
require "cloud_controller/security_context"
require "active_support/core_ext/hash"
require "active_support/core_ext/object/to_query"
require "active_support/json/encoding"
require "cloud_controller/models"
require "cloud_controller/jobs"
require "cloud_controller/background_job_environment"
require "cloud_controller/db_migrator"

require 'stackato/default_org_and_space'

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

      token_information = decode_token(auth_token)

      if token_information
        token_information['user_id'] ||= token_information['client_id']
        uaa_id = token_information['user_id']
      end

      if uaa_id
        user = User.find(guid: uaa_id.to_s)

        unless user
          User.db.transaction do
            user = User.create(guid: uaa_id, active: true)
            VCAP::CloudController::DefaultOrgAndSpace.add_user_to_default_org_and_space(token_information, user)
          end
        end

        update_user_admin_status(token_information, user)
      end

      VCAP::CloudController::SecurityContext.set(user, token_information)
      validate_scheme(user, VCAP::CloudController::SecurityContext.admin?)
    end

    get "/hello/sync" do
      "sync return\n"
    end

    private

    def decode_token(auth_token)
      token_information = @token_decoder.decode_token(auth_token)
      logger.debug2 "Token received from the UAA #{token_information.inspect}"
      token_information
    rescue CF::UAA::TokenExpired
      logger.info('Token expired')
    rescue CF::UAA::DecodeError, CF::UAA::AuthError => e
      logger.warn("Invalid bearer token: #{e.inspect} #{e.backtrace}")
    end

    def validate_scheme(user, admin)
      return unless user || admin

      if @config[:https_required]
        raise Errors::NotAuthorized unless request.scheme == "https"
      end

      if @config[:https_required_for_admins] && admin
        raise Errors::NotAuthorized unless request.scheme == "https"
      end
    end

    def update_user_logged_in_time(token, user)

      login_timestamp = Time.at(token['iat']) rescue nil

      if login_timestamp && user.logged_in_at != login_timestamp
        user.logged_in_at = login_timestamp
        user.save
      end
    end

    def update_user_admin_status(token, user)
      admin = VCAP::CloudController::Roles.new(token).admin?
      user.update_from_hash(admin: admin) if user.admin != admin
    end
  end
end

require "vcap/errors"

require "cloud_controller/config"
require "cloud_controller/db"
require "cloud_controller/runner"
require "cloud_controller/app_observer"
require "cloud_controller/app_stager_task"
require "cloud_controller/controllers"
require "cloud_controller/roles"
require "cloud_controller/encryptor"
require "cloud_controller/blobstore/blobstore"
require "cloud_controller/blobstore/blobstore_url_generator"
require "cloud_controller/dependency_locator"
require "cloud_controller/controller_factory"

require "cloud_controller/legacy_api/legacy_api_base"
require "cloud_controller/legacy_api/legacy_info"
require "cloud_controller/legacy_api/legacy_services"
require "cloud_controller/legacy_api/legacy_service_gateway"
require "cloud_controller/legacy_api/legacy_bulk"

require "cloud_controller/resource_pool"

require "cloud_controller/dea/dea_pool"
require "cloud_controller/dea/dea_client"
require "cloud_controller/dea/dea_respondent"

require "cloud_controller/stager/stager_pool"

require "cloud_controller/health_manager_client"
require "cloud_controller/hm9000_client"
require "cloud_controller/health_manager_respondent"
require "cloud_controller/hm9000_respondent"

require "cloud_controller/task_client"

require "cloud_controller/hashify"
require "cloud_controller/structured_error"
require "cloud_controller/http_request_error"
require "cloud_controller/http_response_error"
