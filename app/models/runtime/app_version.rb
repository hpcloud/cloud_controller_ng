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

    def rollback
      app.droplet_hash = droplet_hash
      app.instances    = instances
      app.version      = version_guid
      app.save
    end

    def self.latest_version(app)
      versions = where( :app => app ).map(:version_count)
      if versions.is_a? Array
        return versions.map { |x| x.to_i }.max
      end

      return 0
    end

    def self.build_description(app)
      pushed_new_code   = app.column_changed?(:droplet_hash)
      changed_instances = app.column_changed?(:instances)

      messages = []
      if pushed_new_code
        messages << "pushed new code"
      end

      if changed_instances
        messages << "changed instances to #{app.instances}"
      end

      messages.join ", "
    end

    def self.make_new_version(app)
      new_version_count = latest_version(app) + 1
      version = new( :app => app, :droplet => app.current_droplet, :version_count => new_version_count, :version_guid => app.version, :instances => app.instances, :description => build_description(app) )
      version.save

      version
    end

    def self.prune_old_versions
      versions_to_keep = VCAP::CloudController::Config.config[:versions_to_keep] || 5

      apps = select_hash_groups(:app_id, :version_count)
      apps.each do |app, versions|
        versions_to_remove = versions.sort.reverse.drop(versions_to_keep)
        versions_to_remove.each do |version|
          where( :app => app, :version_count => version ).destroy
        end
      end
    end

    def self.user_visibility_filter(user)
      {:app => App.user_visible(user)}
    end
  end
end
