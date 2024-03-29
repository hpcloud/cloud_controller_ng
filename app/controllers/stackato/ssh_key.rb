
require "kato/config"

module VCAP::CloudController
  class StackatoSshKeyController < RestController::BaseController

    def get_ssh_key
      ssh_key = Kato::Config.get("cluster", "stackato_ssh_keypair_alluser/privkey")
      if ssh_key
        Yajl::Encoder.encode({
          :sshkey => ssh_key
        })
      else
        raise Errors::ApiError.new_from_details("StackatoSshKeyNotConfigured")
      end
    end

    get "/v2/stackato/ssh_key", :get_ssh_key

  end
end
