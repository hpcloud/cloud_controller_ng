module VCAP::CloudController
  rest_controller :Events do
    define_attributes do
      to_one :space
    end

    query_parameters :timestamp, :type

    def self.default_order_by
      :timestamp
    end
  end
end