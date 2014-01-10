class UploadHandler
  attr_reader :config

  def initialize(config)
    @config = config
  end

  def uploaded_filename(params, resource_name)
    params["#{resource_name}_name"]
  end

  def uploaded_file(params, resource_name)
    if using_nginx?
      file_path = nginx_uploaded_file(params, resource_name)
      # attempt to fall back to Rack to deal with the situation where a file was uploaded via PUT and nginx couldn't handle it, bug #101009
      file_path = rack_temporary_file(params, resource_name) if nginx_file_path.nil? 
      return file_path
    else
      rack_temporary_file(params, resource_name)
    end
  end

  private

  def using_nginx?
    config[:nginx][:use_nginx]
  end

  def nginx_uploaded_file(params, resource_name)
    file_path = params["#{resource_name}_path"]

    UploadedFile.new(file_path) if file_path
  end

  def rack_temporary_file(params, resource_name)
    resource_params = params[resource_name]
    params_are_valid = resource_params.kind_of?(Hash) && resource_params[:tempfile]

    resource_params[:tempfile] if params_are_valid
  end

  class UploadedFile < Struct.new(:path)
  end
end
