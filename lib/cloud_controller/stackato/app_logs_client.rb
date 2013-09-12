
require "cloud_controller/stackato/redis_client"

module VCAP::CloudController
  class StackatoAppLogsClient

    CC_CONFIG_KEY = :app_logs_redis

    def self.configure(config)
      @@cc_config = config
    end

    def self.logger
      @@logger ||= Steno.logger("cc.stackato.app_logs_client")
    end

    def self.redis &block
      StackatoRedisClient.redis &block
    end

    def self.fetch_app_loglines(app, num=25, raw=false)
      key = "apptail.#{app.guid}"
      num = 25 unless num > 0

      loglines = nil
      redis_exception = nil
      loglines = redis { |r| r.lrange(key, 0, num-1) }

      loglines.reverse.map do |record|
        record = Yajl::Parser.parse(record)
        timestamp = record['UnixTime']
        source = record['Source']
        filename = record['LogFilename']
        idx = record['InstanceIndex']
        text = record['Text']
        nodeid = record['NodeID']
        # XXX: `raw` should be part of the logyard record. we
        # shouldn't have to deal with formatting at all.
        if raw
          date = Time.at(timestamp).strftime "%Y-%m-%dT%H:%M:%S%z"
          if idx >= 0
            prefix = "#{app.name}[#{source}.#{idx}]"
          else
            prefix = "#{app.name}[#{source}]"
          end
          "#{date} #{prefix}: #{text}"
        else
          {
            :text => text,
            :source => source,
            :filename => filename,
            :instance => idx,
            :timestamp => timestamp,
            :nodeid => nodeid
          }
        end
      end
    end

    private

  end
end
