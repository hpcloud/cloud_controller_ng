require 'presenters/v3/package_presenter'
require 'handlers/packages_handler'

module VCAP::CloudController
  class PackagesController < RestController::BaseController
    def self.dependencies
      [:packages_handler, :package_presenter, :apps_handler]
    end

    def inject_dependencies(dependencies)
      @packages_handler = dependencies[:packages_handler]
      @package_presenter = dependencies[:package_presenter]
    end

    get '/v3/packages', :list
    def list
      pagination_options = PaginationOptions.from_params(params)
      paginated_result   = @packages_handler.list(pagination_options, @access_context)
      packages_json      = @package_presenter.present_json_list(paginated_result, '/v3/packages')
      [HTTP::OK, packages_json]
    end

    post '/v3/packages/:guid/upload', :upload
    def upload(package_guid)
      message = PackageUploadMessage.new(package_guid, params)
      valid, error = message.validate
      unprocessable!(error) if !valid

      package = @packages_handler.upload(message, @access_context)
      package_json = @package_presenter.present_json(package)

      [HTTP::CREATED, package_json]
    rescue PackagesHandler::InvalidPackageType => e
      invalid_request!(e.message)
    rescue PackagesHandler::SpaceNotFound
      space_not_found!
    rescue PackagesHandler::PackageNotFound
      package_not_found!
    rescue PackagesHandler::Unauthorized
      unauthorized!
    rescue PackagesHandler::BitsAlreadyUploaded
      bits_already_uploaded!
    end

    get '/v3/packages/:guid', :show
    def show(package_guid)
      package = @packages_handler.show(package_guid, @access_context)
      package_not_found! if package.nil?

      package_json = @package_presenter.present_json(package)
      [HTTP::OK, package_json]
    rescue PackagesHandler::Unauthorized
      unauthorized!
    end

    delete '/v3/packages/:guid', :delete
    def delete(package_guid)
      package = @packages_handler.delete(package_guid, @access_context)
      package_not_found! unless package
      [HTTP::NO_CONTENT]
    rescue PackagesHandler::Unauthorized
      unauthorized!
    end

    private

    def package_not_found!
      raise VCAP::Errors::ApiError.new_from_details('ResourceNotFound', 'Package not found')
    end

    def space_not_found!
      raise VCAP::Errors::ApiError.new_from_details('ResourceNotFound', 'Space not found')
    end

    def unauthorized!
      raise VCAP::Errors::ApiError.new_from_details('NotAuthorized')
    end

    def bits_already_uploaded!
      raise VCAP::Errors::ApiError.new_from_details('PackageBitsAlreadyUploaded')
    end

    def unprocessable!(message)
      raise VCAP::Errors::ApiError.new_from_details('UnprocessableEntity', message)
    end

    def invalid_request!(message)
      raise VCAP::Errors::ApiError.new_from_details('InvalidRequest', message)
    end
  end
end
