# Controller to interact with a locally running Stackato AppStore backend.

module VCAP::CloudController
  rest_controller :StackatoAppStoreController do
    path_base "appstore"
    model_class_name :App

    def app_create
      check_maintenance_mode
      body_params = Yajl::Parser.parse(body)
      ensure_params(body_params, ["space_guid", "app_name"])
      validate_app_name(body_params["app_name"])
      # TODO:Stackato: More validation needed
      logger.info("Requesting appstore to create a new app #{body_params}")
      response = invoke_api "/create", {
        :Token => auth_token_header,
        :Space => body_params["space_guid"],
        :AppName => body_params["app_name"]
      }
      Yajl::Encoder.encode({
        :app_guid => response["GUID"]
      })
    end

    def app_deploy(app_guid)
      check_maintenance_mode
      body_params = Yajl::Parser.parse(body)
      params = set_app_deploy_defaults(body_params)
      ensure_params(params, ["app_name", "space_guid", "from"])
      validate_app_name(params["app_name"])
      # TODO:Stackato: More validation needed
      app = find_guid_and_validate_access(:update, app_guid)
      logger.info("Requesting appstore to deploy an app #{params}")
      response = invoke_api "/push", {
        :AppGUID => app.guid,
        :AppName => params["app_name"],
        :Space => params["space_guid"],
        :Url => params["url"],
        :Buildpack => params["buildpack"],
        :Zone => params["zone"],
        :Token => auth_token_header,
        :VcsUrl => params["from"],
        :VcsRef => params["commit"],
        :VcsType => params["type"],
        :AutoStart => params["autostart"],
      }
      # TODO:Stackato: do not just blindly pass repsonse
      Yajl::Encoder.encode(response)
    end

    def ensure_params(params, keys)
      keys.each do |key|
        unless params[key]
          raise Errors::BadQueryParameter.new(key)
        end
      end
    end

    def validate_app_name(app_name)
      if app_name !~ /^[a-zA-Z0-9\-]+$/
        raise Errors::StackatoAppNameInvalid.new
      end
    end

    def set_app_deploy_defaults(params)
      params = params.dup
      # convert null to empty string to workaround
      # http://code.google.com/p/go/issues/detail?id=2540
      params["type"] = "" if params["type"].nil?
      params["type"] = "git" if params["type"].empty?
      # console using the legacy API does not pass 'autostart'
      params["autostart"] = true if params["autostart"].nil?
      params
    end

    def auth_token_header
      env["HTTP_AUTHORIZATION"]
    end

    def invoke_api(path, data)
      status, body = http_post_json "http://127.0.0.1:9256#{path}", data
      if status != 200
        raise Errors::StackatoAppStoreAPIError.new(path, status, body)
      end
      Yajl::Parser.parse(body)
    end

    def http_post_json(url, data)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = 60*5  # TODO: match max_staging_duration+grace?
      request = Net::HTTP::Post.new(uri.request_uri)
      request.content_type = 'application/json'
      request.body = Yajl::Encoder.encode(data)
      begin
        response = http.request(request)
      rescue Errno::ECONNREFUSED
        raise Errors::StackatoAppStoreAPIConnectionFailed.new
      rescue Timeout::Error
	raise Errors::StackatoAppStoreAPITimeout.new
      end
      [response.code.to_i, response.body]
    end

    post '/v2/appstore',               :app_create
    put  '/v2/appstore/:app_guid',     :app_deploy

  end  
end
