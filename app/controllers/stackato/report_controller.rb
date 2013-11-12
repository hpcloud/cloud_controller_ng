
require 'stackato/kato_shell'

module VCAP::CloudController
  class StackatoReportController < RestController::Base
    # TODO:Stackato: Remove this
    allow_unauthenticated_access

    def get_report
      begin
        report_file = KatoShell.report
      rescue Exception => e
        raise Errors::StackatoCreateReportFailed.new(e.message)
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

    get '/v2/stackato/report', :get_report

  end
end