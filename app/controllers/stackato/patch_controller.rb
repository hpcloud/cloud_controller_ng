
require 'stackato/kato_shell'

module VCAP::CloudController
  class StackatoPatchController < RestController::BaseController

    def get_patch_status
      safe_get_patch_status do
        KatoShell.patch_status
      end
    end

    get "/v2/stackato/patch/status", :get_patch_status

    def get_patch_status_json
      safe_get_patch_status do
        KatoShell.patch_status_json
      end
    end

    get "/v2/stackato/patch/status.json", :get_patch_status_json

    private
    
    def safe_get_patch_status
      begin
        yield
      rescue VCAP::Errors::ApiError => e
        if e.name == "ShellOutFailure" && e.message == "Shell out failed: failed to run"
          return [].to_json
        else
          raise
        end
      end
    end

  end
end
