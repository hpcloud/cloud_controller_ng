module VCAP::CloudController
  module Dea
    FileUriResult ||= Class.new(Struct.new(:file_uri_v1, :file_uri_v2, :credentials, :host_ip)) do
      def initialize(opts = {})
        if opts[:file_uri_v2]
          self.file_uri_v2 = opts[:file_uri_v2]
        end
        if opts[:file_uri_v1]
          self.file_uri_v1 = opts[:file_uri_v1]
        end
        if opts[:credentials]
          self.credentials = opts[:credentials]
        end
        if opts[:host_ip]
          self.host_ip = opts[:host_ip]
        end
      end
    end
  end
end
