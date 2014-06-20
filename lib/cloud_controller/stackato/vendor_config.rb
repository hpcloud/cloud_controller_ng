module VCAP::CloudController
  class StackatoVendorConfig

    def self.vendor_version
      f = '/s/code/stackato-version'
      if File.exists? f
        version = File.read(f).strip
        unless version.start_with?("v") # normalize
          version = "v#{version}"
        end
        version
      else
        'UNKNOWN'
      end
    end
  end
end