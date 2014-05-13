require "bcrypt"
require "sinatra"
require "sequel"
require "thin"
require "yajl"
require "delayed_job"

require "allowy"

require "eventmachine/schedule_sync"

require "vcap/common"
require "cf-registrar"
require "vcap/errors/details"
require "vcap/errors/api_error"
require "uaa/token_coder"

require "sinatra/vcap"
require "cloud_controller/security_context"
require "active_support/core_ext/hash"
require "active_support/core_ext/object/to_query"
require "active_support/json/encoding"

<<<<<<< HEAD
      if uaa_id
        user = User.find(:guid => uaa_id.to_s)
        if user.nil?
          User.db.transaction do
            user = User.create(guid: token_information['user_id'], admin: current_user_admin?(token_information), active: true)
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

    def current_user_admin?(token_information)
      if User.count.zero?
        # TODO: evaluate if we want to continue making users admins this way
        admin_email = config[:bootstrap_admin_email]
        admin_email && (admin_email == token_information['email'])
      else
        VCAP::CloudController::Roles.new(token_information).admin?
      end
    end
  end
end
=======
module VCAP::CloudController; end

require "vcap/errors/invalid_relation"
require "vcap/errors/missing_required_scope_error"
require "sequel_plugins/sequel_plugins"
require "vcap/sequel_add_association_dependencies_monkeypatch"
require "access/access"


require "cloud_controller/jobs"
require "cloud_controller/background_job_environment"
require "cloud_controller/db_migrator"
require "cloud_controller/steno_configurer"
require "cloud_controller/constants"
>>>>>>> upstream/master

require "cloud_controller/controller"

require "cloud_controller/config"
require "cloud_controller/db"
require "cloud_controller/runner"
require "cloud_controller/app_observer"
require "cloud_controller/app_stager_task"
require "cloud_controller/controllers"
require "cloud_controller/roles"
require "cloud_controller/encryptor"
require "cloud_controller/blobstore/client"
require "cloud_controller/blobstore/url_generator"
require "cloud_controller/dependency_locator"
require "cloud_controller/controller_factory"
require "cloud_controller/start_app_message"

require "cloud_controller/legacy_api/legacy_api_base"
require "cloud_controller/legacy_api/legacy_info"
require "cloud_controller/legacy_api/legacy_services"
require "cloud_controller/legacy_api/legacy_service_gateway"
require "cloud_controller/legacy_api/legacy_bulk"

require "cloud_controller/resource_pool"

require "cloud_controller/dea/dea_pool"
require "cloud_controller/dea/dea_client"
require "cloud_controller/dea/dea_respondent"

require "cloud_controller/diego/diego_client"

require "cloud_controller/stager/stager_pool"
require "cloud_controller/stager/staging_completion_handler"

require "cloud_controller/hm9000_client"
require "cloud_controller/hm9000_respondent"

require "cloud_controller/task_client"

require "cloud_controller/structured_error"
require "cloud_controller/http_request_error"
require "cloud_controller/http_response_error"

require "cloud_controller/install_buildpacks"
require "cloud_controller/upload_buildpack"

require "services"
