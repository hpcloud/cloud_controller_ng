module VCAP::CloudController
  class AppVersion < Sequel::Model
    many_to_one :app
    many_to_one :droplet

    export_attributes :app_guid, :version_guid, :version_count, :droplet_hash, :description, :instances
    import_attributes :app_guid, :version_guid, :version_count, :droplet_hash, :description, :instances

    def validate
      validates_presence :app
      validates_presence :droplet
      validates_presence :version_count
      validates_presence :version_guid
    end

    def self.user_visibility_filter(user)
      {:app => App.user_visible(user)}
    end
  end
end
