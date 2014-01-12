
require 'stackato/kato_shell'

module VCAP::CloudController
  class StackatoPatchController < RestController::Base

    def get_patch_status
      KatoShell.patch_status
    end

    get "/v2/stackato/patch/status", :get_patch_status

  end
end
