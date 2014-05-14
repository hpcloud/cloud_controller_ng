module VCAP::CloudController
  class QuotaDefinition < Sequel::Model

    one_to_many :organizations

    add_association_dependencies organizations: :destroy

    export_attributes :name, :non_basic_services_allowed, :total_services,
                      :memory_limit, :trial_db_allowed, :allow_sudo,
                      :total_routes, :total_droplets
    import_attributes :name, :non_basic_services_allowed, :total_services,
                      :memory_limit, :trial_db_allowed, :allow_sudo,
                      :total_routes, :total_droplets

    def validate
      validates_presence :name
      validates_unique :name
      validates_presence :non_basic_services_allowed
      validates_presence :total_services
      validates_presence :total_routes
      validates_presence :memory_limit
      validates_presence :allow_sudo
    end

    def before_create
      if self.total_droplets.nil? || self.total_droplets == 0
        self.total_droplets = VCAP::CloudController::Config.config[:droplets_to_keep].to_i
        self.total_droplets = 5 if self.total_droplets <= 0
      end
      super
    end

    def self.configure(config)
      @default_quota_name = config[:default_quota_definition]
    end

    def self.default
      self[:name => @default_quota_name]
    end

    def self.user_visibility_filter(user)
      full_dataset_filter
    end
  end
end
