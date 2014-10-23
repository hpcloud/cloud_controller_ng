require "httpclient"
require "uri"

module VCAP::CloudController
  class FilesController < RestController::ModelController
    path_base "apps"
    model_class_name :App

    get "#{path_guid}/instances/:instance_id/files", :files
    def files(guid, search_param, path = nil, opts = {})
      opts = { "allow_redirect" => true }.merge(params)
      app = find_guid_and_validate_access(:read, guid)

      info = get_file_uri_for_search_param(app, path, search_param)

      headers = {}
      range = env["HTTP_RANGE"]
      if range
        headers["Range"] = range
      end

      http_response = nil
      # new VMC and new DEA, let's hand out the directory server url.
      # We sadly still have to serve the files through CC otherwise
      uri = info.file_uri_v2
      if opts["allow_redirect"] == true
        uri = add_tail(uri) if params.include?("tail")
        return [HTTP::FOUND, {"Location" => uri}, nil]
      else
        if info.host_ip && !info.host_ip.empty?
          if (v2_port = Kato::Config.get('dea_ng', 'directory_server/v2_port'))
            # When possible communicate directly with the DEA node's
            # directory server and avoid re-entering the network.
            uri.sub!(/^(http:\/\/)[a-zA-Z0-9]{32}\..*?(\/instance_paths\/.*)/, '\1' + "#{info.host_ip}:#{v2_port}" + '\2')
          end
        end
        http_response = http_get(uri, headers, nil, nil)
      end

      unless [200, 206, 416].include? http_response.status
        msg = "Request failed for app: #{app.name}, search_param: #{search_param}"
        msg << " as there was an error retrieving the files."

        logger.error("#{msg} For uri:'#{uri}', headers:#{headers} => http status #{http_response.status}")
        raise Errors::ApiError.new_from_details("FileError", msg)
      end

      [http_response.status, http_response.body]
    end

    get "#{path_guid}/instances/:instance_id/files/*", :files
    def http_get(uri, headers, username, password)
      client = HTTPClient.new
      client.set_auth(nil, username, password) if username && password
      client.get(uri, :header => headers)
    end

    private
    # @param [String, URI::Generic] uri
    # @return [String] uri with tail=<whatever> added to query string
    def add_tail(uri)
      uri = URI(uri)
      # query is Array of [key, value1, value2...]
      query = URI::decode_www_form(uri.query || "")
      unless query.assoc("tail")
        query.push(["tail", ""])
      end
      uri.query = URI::encode_www_form(query)
      uri.to_s
    end

    def get_file_uri_for_search_param(app, path, search_param)
      # Do we really want/need to be accepting a + here?  It is pretty
      # harmless, but it is weird.  Getting rid of it would require checking
      # with the VMC and STS teams to make sure no one expects to be able to
      # send a +.
      match = search_param.match(/^[+]?([0-9]+)$/)
      if match
        instance = match.captures[0].to_i
        DeaClient.get_file_uri_for_active_instance_by_index(app, path, instance)
      elsif search_param.match(/^[0-9a-zA-z]+$/)
        DeaClient.get_file_uri_by_instance_guid(app, path, search_param)
      else
        msg = "Request failed for app: #{app.name}, path: #{path || '/'}"
        msg << " as the search_param: #{search_param} is invalid."

        raise Errors::ApiError.new_from_details("FileError", msg)
      end
    end
  end
end
