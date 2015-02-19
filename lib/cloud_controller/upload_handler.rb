class UploadHandler
  attr_reader :config

  def initialize(config)
    @config = config
  end

  def uploaded_filename(params, resource_name)
    params["#{resource_name}_name"]
  end

  def uploaded_file(params, resource_name)
    if using_nginx? || using_stackato_upload_handler?
      # Attempt to fall back to Rack to deal with the situation where a file was
      # uploaded via PUT and nginx couldn't handle it, bug #101009
      nginx_uploaded_file(params, resource_name) || rack_temporary_file(params, resource_name)
    else
      rack_temporary_file(params, resource_name)
    end
  end

  private

  def using_nginx?
    config[:nginx][:use_nginx] rescue false
  end

  def using_stackato_upload_handler?
    config[:stackato_upload_handler][:enabled] rescue false
  end

  def nginx_uploaded_file(params, resource_name)
    params["#{resource_name}_path"]
  end

  def rack_temporary_file(params, resource_name)
    resource_params = params[resource_name]
    return unless resource_params.respond_to?(:[])

    tempfile = resource_params[:tempfile] || resource_params["tempfile"]
    tempfile.respond_to?(:path) ? tempfile.path : tempfile
  end
end
