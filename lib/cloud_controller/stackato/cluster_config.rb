module VCAP::CloudController
  class StackatoClusterConfig

    # Utilities for getting config info about the cluster
    
    def self.update_license_info(info, license)
      no_license_required = Kato::Config.get("cluster", "no_license_required")
      free_license = Kato::Config.get("cluster", "free_license")
      if Kato::Config.get("cluster", "license_checking") != false
        if license.is_a?(Hash)
          info[:license] = displayable_license_subset(license)
        else
          info[:license] = {}
          default_value = no_license_required || free_license
          if default_value
            info[:license][:memory_limit] = default_value
          end
        end
        info[:license][:memory_in_use] = display_memory_in_gb(memory_in_use)
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
        license.slice("organization", "serial", "memory_limit")
    end
    
  end
end