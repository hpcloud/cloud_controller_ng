class VCAP::Errors::AppVersionNotFound < Exception; end

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
      begin
        body_params = Yajl::Parser.parse(body)
        code_only = body_params.fetch('code_only', false)
      rescue
        logger.debug("failed to read body: #{$!}")
        code_only = false
      end
      if version
        version.rollback(code_only)
        return [204, {}, nil]
      else
        logger.warn "Unable to find version #{guid} for app"
        raise VCAP::Errors::BadQueryParameter.new
      end
    end
  end
end
