
require "kato/config"
require "httpclient"
require "open-uri"

module VCAP::CloudController
  class StackatoAppStoresController < RestController::BaseController

    APP_STORES_BASE_URL = "/v2/stackato/app_stores"
    DEFAULT_INLINE_RELATIONS_DEPTH = 0
    PROXY_VARS = %W{http_proxy https_proxy no_proxy};

    def list
      store_config = load_store_config
      proxy_config = store_config["proxy"]
      fetch_content = fetch_store_content?

      resources = []
      # TODO:Stackato: Make requests concurrent
      store_config["stores"].each do |store_name, store|
        resources << construct_resource(store_name, store, fetch_content, proxy_config)
      end

      Yajl::Encoder.encode({
        :total_results => resources.size,
        :total_pages   => 1,
        :prev_url => nil,
        :next_url => nil,
        :resources => resources,
        :default_icon => store_config["default_icon"],
      })
    end

    def get(store_name)
      store_config = load_store_config
      validate_store_exists(store_config["stores"], store_name)

      proxy_config = store_config["proxy"]

      store = store_config["stores"][store_name]
      resource = construct_resource(store_name, store, fetch_store_content?, proxy_config)

      Yajl::Encoder.encode(resource)
    end

    def verify_ssl(store)
      if store.has_key?("verify_ssl") && store["verify_ssl"]
        OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
      else
        OpenSSL::SSL::VERIFY_NONE
      end
    end

    def construct_resource(store_name, store, fetch_content, proxy_config)
      entity = {
        :content_url => store["content_url"],
        :enabled => store["enabled"],
        :verify_ssl => store["verify_ssl"]
      }
      if fetch_content
        begin

          # setup proxy environment variables for URI.find_proxy
          env = {}
          PROXY_VARS.each do |name|
            env[name] = ENV.delete(name)
            if proxy_config
              value = proxy_config[name]
              ENV[name] = value unless value.nil? || value.empty?
            end
          end

          uri = URI.parse( store["content_url"] )
          begin
            proxy = uri.find_proxy
          rescue
            proxy = nil
          end

          # restore proxy environment variables
          PROXY_VARS.each do |name|
            ENV.delete(name)
            ENV[name] = env[name] unless env[name].nil?
          end

          proxy ||= URI.parse("")
          http = Net::HTTP::Proxy(proxy.host, proxy.port, proxy.user, proxy.password)
          if uri.scheme == 'https'
            http.use_ssl = true
            http.verify_mode = verify_ssl(store)
          end

          content = http.start(uri.host, uri.port).request_get(uri.request_uri).body

          # XXX:TODO:Stackato: Replace with YAML.safe_load (https://github.com/tenderlove/psych/issues/119)
          store_content = YAML.load(content)
          entity[:content] = {
            :store => store_content["store"],
            :apps  => store_content["apps"]
          }
        rescue Exception => e
          logger.error(
            "Exception #{e.inspect}" +
            " raised while trying to get #{store["content_url"]}, skipping"
          )
          # probably a bad url
          entity[:error] = true
        end
      end
      return {
        :metadata => {
          :name => store_name,
          :url => store_url(store_name)
        },
        :entity => entity
      }
    end

    def store_url(store_name)
      [APP_STORES_BASE_URL, store_name].join("/")
    end

    def fetch_store_content?
      (params["inline-relations-depth"] || DEFAULT_INLINE_RELATIONS_DEPTH).to_i > 0 \
        rescue false
    end

    def add
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      check_maintenance_mode
      new_store = Yajl::Parser.parse(body)
      store_config = load_store_config
      new_store["verify_ssl"] = new_store["verify_ssl"] || true # XXX expose in web UI
      validate_store_name(new_store["name"])
      validate_store_content_url(new_store["content_url"])
      validate_store_enabled(new_store["enabled"])
      validate_store_verify_ssl(new_store["verify_ssl"])
      validate_store_not_exists(store_config["stores"], new_store["name"])
      save_store(new_store["name"], new_store["content_url"], new_store["enabled"], new_store["verify_ssl"])

      proxy_config = store_config["proxy"]
      new_resource = construct_resource(
        new_store["name"],
        {
          "content_url" => new_store["content_url"],
          "enabled" => new_store["enabled"],
          "verify_ssl" => new_store["verify_ssl"]
        },
        fetch_store_content?, proxy_config
      )

      # Return HTTP 201 (Created) and set the Location header to URL of resource
      [
        201,
        { "Location" => store_url(new_store["name"]) },
        Yajl::Encoder.encode(new_resource)
      ]
    end

    def update(store_name)
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      check_maintenance_mode
      store_config = load_store_config
      validate_store_name(store_name)
      validate_store_exists(store_config["stores"], store_name)
      store = store_config["stores"][store_name]
      updates = Yajl::Parser.parse(body)
      if updates.has_key? "content_url"
        validate_store_content_url(updates["content_url"])
        store["content_url"] = updates["content_url"]
      end
      if updates.has_key? "enabled"
        validate_store_enabled(updates["enabled"])
        store["enabled"] = updates["enabled"]
      end
      if updates.has_key? "verify_ssl"
        validate_store_verify_ssl(updates["verify_ssl"])
        store["verify_ssl"] = updates["verify_ssl"]
      end
      save_store(store_name, store["content_url"], store["enabled"], store["verify_ssl"])

      # Return the updated store resource
      get(store_name)
    end

    def delete(store_name)
      raise Errors::ApiError.new_from_details("NotAuthorized") unless roles.admin?
      check_maintenance_mode
      store_config = load_store_config
      validate_store_name(store_name)
      validate_store_exists(store_config["stores"], store_name)
      delete_store(store_name)
      [204, {}, nil]
    end

    def load_store_config
      store_config = Kato::Config.get("cloud_controller_ng", "app_store")
      unless store_config and store_config.is_a? Hash and store_config["stores"]
        raise Errors::ApiError.new_from_details("StackatoAppStoresNotConfigured")
      end
      store_config
    end

    def validate_store_name(store_name)
      unless store_name.is_a? String and store_name.size > 1
        raise Errors::ApiError.new_from_details("StackatoAppStoreValidNameRequired")
      end
    end

    def validate_store_content_url(content_url)
      unless content_url.is_a? String and content_url.size > 1
        raise Errors::ApiError.new_from_details("StackatoAppStoreValidContentUrlRequired")
      end
    end

    def validate_store_enabled(enabled)
      unless [false, true].include? enabled
        raise Errors::ApiError.new_from_details("StackatoAppStoreValidEnabledRequired")
      end
    end

    def validate_store_verify_ssl(enabled)
      unless [false, true].include? enabled
        raise Errors::ApiError.new_from_details("StackatoAppStoreValidSSLVerifyRequired")
      end
    end

    def validate_store_not_exists(existing_stores, store_name)
      if existing_stores[store_name]
        raise Errors::ApiError.new_from_details("StackatoAppStoreExists", store_name)
      end
    end

    def validate_store_exists(existing_stores, store_name)
      unless existing_stores[store_name]
        raise Errors::ApiError.new_from_details("StackatoAppStoreDoesNotExist", store_name)
      end
    end

    def save_store(store_name, content_url, enabled, verify_ssl)
      Kato::Config.set("cloud_controller_ng", "app_store/stores/#{store_name}", {
        :content_url => content_url,
        :enabled => enabled,
        :verify_ssl => verify_ssl
      })
    end

    def delete_store(store_name)
      Kato::Config.del("cloud_controller_ng", "app_store/stores/#{store_name}")
    end

    get     APP_STORES_BASE_URL,                  :list
    post    APP_STORES_BASE_URL,                  :add
    get     "#{APP_STORES_BASE_URL}/:store_name", :get
    put     "#{APP_STORES_BASE_URL}/:store_name", :update
    delete  "#{APP_STORES_BASE_URL}/:store_name", :delete

  end
end
