module VCAP::CloudController
  class StackatoClusterConfig

    # Utilities for getting config info about the cluster
    
    def self.update_license_info(info, license)
      if Kato::Config.get("cluster", "license_checking") == false
        return
      end
      if license.is_a?(Hash)
        info[:license] = displayable_license_subset(license)
      else
        info[:license] = {}
        no_license_memory_limit = Kato::Config.get("cluster", "memory_limits/no_license_required")
        if (0 + no_license_memory_limit rescue nil).nil?
            no_license_memory_limit = Kato::Constants::MEMORY_LIMIT_NO_LICENSE_REQUIRED
        end
        info[:license][:memory_limit] = no_license_memory_limit
      end
      info[:license][:memory_in_use] = display_memory_in_gb(memory_in_use)
      state, url = get_memory_usage_info(license, info[:license][:memory_in_use], info[:license][:memory_limit])
      info[:license][:state] = state
      info[:license][:url] = url if url
    end
    
    def self.get_memory_usage_info(license, memory_in_use, memory_limit)
      if memory_in_use <= memory_limit
        [!license.is_a?(Hash) ?
          Kato::Constants::LICENSE_STATE_NO_LICENSE_COMPLIANT :
           Kato::Constants::LICENSE_STATE_HAS_LICENSE_COMPLIANT, nil]
      else
        free_license_memory_limit = Kato::Config.get("cluster", "memory_limits/free_license")
        if (0 + free_license_memory_limit rescue nil).nil?
            free_license_memory_limit = Kato::Constants::MEMORY_LIMIT_FREE_LICENSE
        end
        if !license.is_a?(Hash)
          if memory_in_use <= free_license_memory_limit
            [Kato::Constants::LICENSE_STATE_NO_LICENSE_NONCOMPLIANT_UNDER_FREE_MEMORY,
             Kato::Constants::LICENSE_URL_FREE_LICENSE_URL]
          else
            [Kato::Constants::LICENSE_STATE_NO_LICENSE_NONCOMPLIANT_OVER_FREE_MEMORY,
             Kato::Constants::LICENSE_URL_PURCHASE_LICENSE_URL]
          end
        else
          [Kato::Constants::LICENSE_STATE_HAS_LICENSE_NONCOMPLIANT,
           Kato::Constants::LICENSE_URL_UPGRADE_LICENSE_URL]
        end
      end
    end
    
    def self.memory_in_use
      # Return memory in use in bytes
      config = Kato::Config.get("cluster", "memory")
      return 0 unless config
      node_keys = config.keys.find_all{|x| x =~ /\A\d+(?:\.\d+){3}\z/ }
      node_keys.map { |k| config[k].to_i }.reduce(:+) * 1024
    end
    
    def self.display_memory_in_gb(mem)
      (mem.to_f / 2 ** 30).round
    end
    
    def self.displayable_license_subset(license)
      license.slice("organization", "serial", "memory_limit").symbolize_keys
    end
    
  end
end