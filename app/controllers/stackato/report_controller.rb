
require 'stackato/kato_shell'

module VCAP::CloudController
  class StackatoReportController < RestController::Base
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
    
    def redis_key_for_token(token)
      "cc:report_controller:token:#{token}"
    end

    def add_token(token)
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      period = 60
      logger.info "Adding token #{token} expiring after #{period} seconds"
      EphemeralRedisClient.redis do |r|
        r.set redis_key_for_token(token), "empty"
        r.expire redis_key_for_token(token), period
      end
    end

    def get_report_with_token_auth(token)

      EphemeralRedisClient.redis do |r|
        data = r.get redis_key_for_token(token)
        if data.nil?
          raise Errors::ApiError.new_from_details("StackatoCreateReportFailed", "Invalid or expired token")
        end
        r.del redis_key_for_token(token)
      end
      
      send_report
    end

    def get_report_with_standard_auth
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      send_report
    end

    get '/v2/stackato/report',  :get_report_with_standard_auth
    put '/v2/stackato/report/token/:token', :add_token
    get '/v2/stackato/report/file/:token',  :get_report_with_token_auth
  end
end
