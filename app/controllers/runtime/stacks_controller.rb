module VCAP::CloudController
  class StacksController < RestController::ModelController
    query_parameters :name

    def self.default_order_by
      :name
    end

    get path, :enumerate
    get path_guid, :read
  end
end
