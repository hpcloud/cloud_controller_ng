module VCAP::CloudController
  class AppVersion < Sequel::Model
    many_to_one :app

    export_attributes :app_guid, :version_guid
    import_attributes :app_guid, :version_guid

    def validate
      validates_presence :app
      validates_presence :version_guid
    end

    def self.user_visibility_filter(user)
      {:app => App.user_visible(user)}
    end
  end
end
