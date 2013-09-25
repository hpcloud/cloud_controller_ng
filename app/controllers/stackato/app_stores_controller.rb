
require "kato/config"
require "httpclient"

module VCAP::CloudController
  class StackatoStoresController < RestController::Base
    # TODO:Stacakto: Remove this
    allow_unauthenticated_access

    APP_STORES_BASE_URL = "/v2/stackato/app_stores"

    def get_app_stores
      store_config = Kato::Config.get("cloud_controller_ng", "app_store")
      unless store_config
        raise Errors::StackatoAppStoresNotConfigured.new
      end
      proxy_config = store_config["proxy"]

      resources = []
      # TODO:Stackato: Make requests concurrent
      store_config["stores"].each do |store_name, store|
        next unless store["enabled"]
        resources << fetch_store(store_name, store, proxy_config)      
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

    def fetch_store(store_name, store, proxy_config)
      entity = {
        :content_url => store["url"],
        :enabled => store["enabled"]
      }
      begin
        if proxy_config and proxy_config.has_key? "authorization"
          proxy = "http://#{proxy_config["host"]}:#{proxy_config["port"]}"
          http_client = HTTPClient.new(proxy)
          http_client.set_proxy_auth(
            proxy_config["username"],
            proxy_config["password"]
          )
        else
          http_client = HTTPClient.new
        end
        content = http_client.get_content(store["url"])
        # XXX:TODO:Stackato: Replace with YAML.safe_load (https://github.com/tenderlove/psych/issues/119)
        store_content = YAML.load(content)
        entity[:content] = {
          :store => store_content["store"],
          :apps  => store_content["apps"]
        }
      rescue Exception => e
        logger.error(
          "Exception #{e.inspect}" +
          " raised while trying to get #{store["url"]}, skipping"
        )
        # probably a bad url
        entity[:error] = true
      end
      return {
        :metadata => {
          :name => store_name,
          #:url => "#{APP_STORES_BASE_URL}/#{store_name}"
        },
        :entity => entity
      }      
    end

    get APP_STORES_BASE_URL, :get_app_stores

  end
end
