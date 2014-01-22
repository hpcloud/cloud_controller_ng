require "vcap/rest_api/errors"
require "yaml"

module VCAP::Errors
  include VCAP::RestAPI::Errors

  ["vendor", "stackato"].each do |source|
    errors_dir = File.expand_path("../../../#{source}/errors", __FILE__)
    YAML.load_file("#{errors_dir}/v2.yml").each do |code, meta|
      define_error meta["name"], meta["http_code"], code, meta["message"]
    end
  end

end
