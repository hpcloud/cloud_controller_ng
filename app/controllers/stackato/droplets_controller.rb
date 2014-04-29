module VCAP::CloudController
  class DropletsController < RestController::ModelController
    define_attributes do
      to_one    :app
      to_many   :versions
      attribute :droplet_hash, String
    end

    query_parameters :droplet_hash

    define_messages
    define_routes
  end
end
