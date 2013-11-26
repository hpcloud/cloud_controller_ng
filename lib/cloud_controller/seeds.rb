module VCAP::CloudController
  module Seeds
    class << self
      def write_seed_data(config)
        create_seed_quota_definitions(config)
        create_seed_stacks(config)
        system_org = create_seed_organizations(config)
        create_seed_domains(config, system_org)
      end

      def create_seed_quota_definitions(config)
        return if QuotaDefinition.count > 0
        config[:quota_definitions].each do |k, v|
          QuotaDefinition.update_or_create(:name => k.to_s) do |r|
            r.update_from_hash(v)
          end
        end
      end

      def create_seed_stacks(config)
        return if Stack.count > 0
        Stack.populate
      end

      def create_seed_organizations(config)
        return if Organization.count > 0
        # It is assumed that if no system domain organization is present,
        # then the 'system domain' feature is unused.
        return unless config[:system_domain_organization]

        quota_definition = QuotaDefinition.find(:name => "paid")

        unless quota_definition
          raise ArgumentError, "Missing 'paid' quota definition in config file"
        end

        Organization.find_or_create(:name => config[:system_domain_organization]) do |org|
          org.quota_definition = quota_definition
        end
      end

      def create_seed_domains(config, system_org)
        return if Domain.count > 0
        Domain.populate_from_config(config, system_org)
      end
    end
  end
end
