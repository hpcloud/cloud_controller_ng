module VCAP::CloudController::Models
  class Session < Sequel::Model
    many_to_one :app

    export_attributes :public_key, :app_guid
    import_attributes :public_key, :app_guid

    def space
      app.space
    end

    def after_commit
      VCAP::CloudController::DeaClient.start_ssh(self)
    end

    def after_destroy
      VCAP::CloudController::DeaClient.stop_ssh(self)
    end

    def self.user_visibility_filter(user)
      user_visibility_filter_with_admin_override(
        :app => App.filter(:space => user.spaces_dataset))
    end
  end
end
