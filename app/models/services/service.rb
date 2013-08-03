# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController::Models
  class Service < Sequel::Model
    plugin :serialization

    one_to_many :service_plans
    one_to_one  :service_auth_token, :key => [:label, :provider], :primary_key => [:label, :provider]

    add_association_dependencies :service_plans => :destroy

    default_order_by  :label

    export_attributes :label, :provider, :url, :description,
                      :version, :info_url, :active, :bindable,
                      :unique_id, :extra, :tags

    import_attributes :label, :provider, :url, :description,
                      :version, :info_url, :active, :bindable,
                      :unique_id, :extra, :tags

    strip_attributes  :label, :provider

    def validate
      validates_presence :label
      validates_presence :provider
      validates_presence :url
      validates_presence :description
      validates_presence :version
      validates_presence :bindable
      validates_url      :url
      validates_url      :info_url
      validates_unique   [:label, :provider]
    end

    serialize_attributes :json, :tags

    alias_method :bindable?, :bindable

    def self.user_visibility_filter(current_user)
      plans_I_can_see = ServicePlan.filter(ServicePlan.user_visibility_filter(current_user))
      opts = {id: plans_I_can_see.map(&:service_id).uniq}
      user_visibility_filter_with_admin_override(opts)
    end

    def tags
      super || []
    end
  end
end
