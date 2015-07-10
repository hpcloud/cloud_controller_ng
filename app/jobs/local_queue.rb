require 'kato/local/node'

module VCAP::CloudController
  module Jobs
    class LocalQueue < Struct.new(:config)
      NODE_ID = Kato::Local::Node.get_local_node_id
      def to_s
        "cc-" + NODE_ID
      end
    end
  end
end
