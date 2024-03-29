
require 'digest/md5'
require "cloud_controller/stackato/redis_client"

module VCAP::CloudController
  class StackatoCloudeventsController < RestController::BaseController

    def get_cloudevents
      num = params["n"].to_i
      num = 25 unless num > 0
      events_list =  redis { |r| r.lrange("cloud_events", 0, num-1) }
      since_md5 = params["since_md5"]

      filtered_events = []
      events_list.each do |event|
        digest = Digest::MD5.hexdigest(event)
        if since_md5 == digest
          # this and all following events have been seen already.
          break
        end
        begin
          event_hash = Yajl::Parser.parse(event)
          event_hash[:md5] = digest
          filtered_events << event_hash
        rescue
          logger.warn("StackatoCloudeventsController: Can't Yaml-parse event '#{event}': #{$!}")
        end
      end
      Yajl::Encoder.encode({ :results => filtered_events })
    end

    def redis &block
      AppLogsRedisClient.redis &block
    end

    get "/v2/stackato/cloudevents", :get_cloudevents

  end
end
