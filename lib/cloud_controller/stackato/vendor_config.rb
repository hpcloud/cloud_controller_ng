module VCAP::CloudController
  class StackatoVendorConfig

    # Get the vendor version by reading the top-level GITDESCRIBE file.
    # This file is expected by generated by the install script using the
    # `git describe` command.
    def self.vendor_version
      f = File.absolute_path File.join(__FILE__, '..', '..', '..', '..', 'GITDESCRIBE')
      if File.exists? f
        File.read(f).strip
      else
        'UNKNOWN'
      end
    end
  end
end