module VCAP::CloudController
  class QuotaDefinition < Sequel::Model
    one_to_many :organizations

    attr_accessor :org_usage

    export_attributes :name, :non_basic_services_allowed, :total_services, :total_routes,
                      :memory_limit, :trial_db_allowed, :instance_memory_limit,
                      :allow_sudo, :total_droplets
    import_attributes :name, :non_basic_services_allowed, :total_services, :total_routes,
                      :memory_limit, :trial_db_allowed, :instance_memory_limit,
                      :allow_sudo, :total_droplets

    def validate
      validates_presence :name
      validates_unique :name
      validates_presence :non_basic_services_allowed
      validates_presence :total_services
      validates_presence :total_routes
      validates_presence :memory_limit
      validates_presence :allow_sudo
      errors.add(:memory_limit, :less_than_zero) if memory_limit && memory_limit < 0
      errors.add(:instance_memory_limit, :invalid_instance_memory_limit) if instance_memory_limit && instance_memory_limit < -1
    end

    def before_destroy
      if organizations.present?
        raise VCAP::Errors::ApiError.new_from_details('AssociationNotEmpty', 'organization', 'quota definition')
      end
    end

    def before_create
      ensure_total_droplets_is_positive
      super
    end

    def after_save
      ensure_total_droplets_is_positive
      super
    end

    def trial_db_allowed=(_)
    end

    def trial_db_allowed
      false
    end

    def self.configure(config)
      @default_quota_name = config[:default_quota_definition]
      @config = config
    end

    def to_hash(opts={})
      return super(opts) unless org_usage

      super(opts).merge!('org_usage' => org_usage)
    end

    class << self
      attr_reader :default_quota_name
    end

    def self.default
      self[name: @default_quota_name]
    end

    def self.user_visibility_filter(user)
      full_dataset_filter
    end

    class << self
      attr_accessor :config
    end
    
    def ensure_total_droplets_is_positive
      if self.total_droplets.nil? || self.total_droplets == 0
        self.total_droplets = self.class.config[:droplets_to_keep].to_i
        self.total_droplets = 5 if self.total_droplets <= 0
      end
    end
  end
end
