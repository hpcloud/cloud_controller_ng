
require "kato/config"

module VCAP::CloudController
  class StackatoSshKeyController < RestController::Base
    # TODO:Stackato: Remove unauthorized access when stackato
    #                client passes auth token.
    allow_unauthenticated_access

    def get_ssh_key
      ssh_key = Kato::Config.get("cluster", "stackato_ssh_keypair_alluser/privkey")
      if ssh_key
        Yajl::Encoder.encode({
          :sshkey => ssh_key
        })
      else
        raise Errors::StackatoSshKeyNotConfigured.new
      end
    end

    get "/v2/stackato/ssh_key", :get_ssh_key

  end
end
