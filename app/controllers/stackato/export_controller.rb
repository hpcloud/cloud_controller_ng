
require 'stackato/kato_shell'

module VCAP::CloudController
  class StackatoExportController < RestController::BaseController

    def export
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      file = KatoShell.export params["regen"]
      export_filename = 'stackato-export.tgz'
      if params["hostname"]
        export_filename = "#{params["hostname"]}-export.tgz"
      end
      send_file(
        file,
        :filename => export_filename,
        :type => "application/x-compressed"
      )
    end

    def export_info
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      Yajl::Encoder.encode({
        :export_available   => KatoShell.export_exists?,
        :export_in_progress => KatoShell.export_in_progress?
      })
    end

    get '/v2/stackato/export', :export
    get '/v2/stackato/export_info', :export_info

  end
end
