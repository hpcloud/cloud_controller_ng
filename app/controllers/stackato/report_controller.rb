
require 'stackato/kato_shell'

module VCAP::CloudController
  class StackatoReportController < RestController::BaseController
    allow_unauthenticated_access

    def send_report
      begin
        report_file = KatoShell.report
      rescue Exception => e
        raise Errors::ApiError.new_from_details("StackatoCreateReportFailed", e.message)
      end

      report_filename = 'stackato-report.tgz'
      if params['hostname']
        report_filename = "#{params['hostname']}-report.tgz"
      end

      send_file(
          report_file,
          :type => 'application/x-compressed',
          :filename => report_filename
      )
    end

    def get_report_with_standard_auth
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      send_report
    end

    get '/v2/stackato/report',  :get_report_with_standard_auth
  end
end
