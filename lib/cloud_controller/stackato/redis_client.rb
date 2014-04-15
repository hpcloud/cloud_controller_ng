
module VCAP::CloudController
  class EphemeralRedisClient
    def self.configure(config)
      @@cc_config = config
    end

    def self.logger
      @@logger ||= Steno.logger("cc.stackato.redis_client.#{config_key}")
    end

    def self.config_key
      :ephemeral_redis
    end

    def self.mutex
      @@mutex ||= Mutex.new
    end

    def self.redis
      # Only allow one thread to use the redis client at a time.
      # Redis processes requests serially, so no benefit to having more than
      # a single connection to Redis.
      mutex.synchronize do

        # Create connection to Redis, if we do not already have an active
        # connection.
        @@redis ||= nil
        unless @@redis and @@redis.client.connected?
          redis_config = @@cc_config[config_key]
          unless redis_config.is_a? Hash and redis_config[:host] and redis_config[:port]
            raise Errors::StackatoRedisClientNotConfigured.new
          end
          host = redis_config[:host].sub "127.0.0.1", VCAP.local_ip
          logger.info("Connecting to redis at #{host}:#{redis_config[:port]}")
          @@redis = Redis.new(
            :host => host,
            :port => redis_config[:port],
            :password => redis_config[:password]
          )
        end

        # Process redis call in a block. This allows us to wrap in mutex, so that
        # only one thread will use the connection at a time.
        yield @@redis

      end

    end
  end

  class AppLogsRedisClient
    def self.configure(config)
      @@cc_config = config
    end

    def self.logger
      @@logger ||= Steno.logger("cc.stackato.redis_client.#{config_key}")
    end

    def self.config_key
      :app_logs_redis
    end

    def self.mutex
      @@mutex ||= Mutex.new
    end

    def self.redis
      # Only allow one thread to use the redis client at a time.
      # Redis processes requests serially, so no benefit to having more than
      # a single connection to Redis.
      mutex.synchronize do

        # Create connection to Redis, if we do not already have an active
        # connection.
        @@redis ||= nil
        unless @@redis and @@redis.client.connected?
          redis_config = @@cc_config[config_key]
          unless redis_config.is_a? Hash and redis_config[:host] and redis_config[:port]
            raise Errors::StackatoRedisClientNotConfigured.new
          end
          logger.info("Connecting to redis at #{redis_config[:host]}:#{redis_config[:port]}")
          @@redis = Redis.new(
            :host => redis_config[:host],
            :port => redis_config[:port],
            :password => redis_config[:password]
          )
        end

        # Process redis call in a block. This allows us to wrap in mutex, so that
        # only one thread will use the connection at a time.
        yield @@redis

      end

    end
  end

end
