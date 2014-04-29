module VCAP::CloudController
  class AppVersionsController < RestController::ModelController
    path_base "apps"

    define_attributes do
      to_one    :app
      to_one    :droplet
      attribute :version_guid, String
      attribute :droplet_hash, String
      attribute :version_count, Integer
      attribute :description, String
    end

    query_parameters :app_guid, :version_guid, :description, :instances, :version_count, :droplet_hash

    def delete(guid)
      do_delete(find_guid_and_validate_access(:delete, guid))
    end

    post "#{path_guid}/rollback/:version", :rollback

    def rollback(guid, version)
      version.gsub!("v", "")

      app = find_guid_and_validate_access(:update, guid, App)
      verion = app.versions.where( :version_count => version )

      if version
        version.rollback
        return [204, {}, nil]
      else
        logger.warn "Unable to find version #{version} for app with guid #{guid}"
        raise VCAP::Errors::BadQueryParameter.new
      end
    end

    define_messages
    define_routes
  end
end
