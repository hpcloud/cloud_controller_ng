
module VCAP::CloudController
  class StackatoAppLogsClient

    CC_CONFIG_KEY = :app_logs_redis

    def self.configure(config)
      @@cc_config = config
    end

    def self.logger
      @@logger ||= Steno.logger("cc.stackato.app_logs_client")
    end

    def self.redis_client
      @@redis ||= nil
      unless @@redis and @@redis.client.connected?
        redis_config = @@cc_config[CC_CONFIG_KEY]
        unless redis_config.is_a? Hash and redis_config[:host] and redis_config[:port]
          raise Errors::StackatoAppLogsRedisNotConfigured.new
        end
        logger.info("Connecting to app_logs redis at #{redis_config[:host]}:#{redis_config[:port]}")
        @@redis = Redis.new(
          :host => redis_config[:host],
          :port => redis_config[:port],
          :password => redis_config[:password]
        )
      end
      @@redis
    end

    def self.fetch_app_loglines(app, num=25, raw=false)
      key = "apptail.#{app.guid}"
      num = 25 unless num > 0

      loglines = nil
      redis_exception = nil
      redis_client_mutex.synchronize do
        begin
          loglines = redis_client.lrange(key, 0, num-1)
        rescue Redis::BaseError => e
          @@redis = nil
          redis_exception = e
        end
      end
      raise redis_exception if redis_exception

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

    def self.redis_client_mutex
      @@redis_mutex ||= Mutex.new
    end

  end
end
