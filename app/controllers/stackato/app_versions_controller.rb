module VCAP::CloudController
  class AppVersionsController < RestController::ModelController
    define_attributes do
      to_one    :app
      attribute :version_count, Integer
      attribute :description, String
    end

    query_parameters :app_guid, :description, :instances, :memory, :version_count

    define_messages
    define_routes

    post "#{path_guid}/rollback", :rollback_version
    def rollback_version(guid)
      version = find_guid_and_validate_access(:update, guid)
      app = VCAP::CloudController::App.find(guid: version.app_guid)
      begin
        body_params = Yajl::Parser.parse(body)
        code_only = body_params.fetch('code_only', false)
      rescue
        logger.debug("failed to read body: #{$!}")
        code_only = false
      end
      if version
        version.rollback(code_only)

        name = app[:name]
        event = {
          :user => SecurityContext.current_user,
          :app => app,
          :version => version,
          :event => 'APP_VERSION_ROLLED_BACK',
          :instance_index => -1,
          :message => "Rolled back app '#{app.name}'"
        }
        logger.info("TIMELINE #{event.to_json}")
        return [204, {}, nil]
      else
        logger.warn "Unable to find version #{guid} for app"
        raise Errors::ApiError.new_from_details("BadQueryParameter")
      end
    end
  end
end
