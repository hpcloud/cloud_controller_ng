
require 'stackato/kato_shell'

module VCAP::CloudController
  class StackatoReportController < RestController::Base
    allow_unauthenticated_access
    
    def redis_key_for_token(token)
      "cc:report_controller:token:#{token}"
    end

    def add_token(token)
      raise Errors::NotAuthorized unless roles.admin?
      period = 60
      logger.info "Adding token #{token} expiring after #{period} seconds"
      EphemeralRedisClient.redis do |r|
        r.set redis_key_for_token(token), "empty"
        r.expire redis_key_for_token(token), period
      end
    end

    def get_report(token)
      EphemeralRedisClient.redis do |r|
        data = r.get redis_key_for_token(token)
        if data.nil?
          raise Errors::StackatoCreateReportFailed.new("Invalid or expired token")
        end
        r.del redis_key_for_token(token)
      end
      
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

    put '/v2/stackato/report/token/:token', :add_token
    get '/v2/stackato/report/file/:token',  :get_report

  end
end