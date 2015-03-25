require 'presenters/v3/app_presenter'
require 'handlers/apps_handler'
require 'cloud_controller/paging/pagination_options'

module VCAP::CloudController
  class AppsV3Controller < RestController::BaseController
    class InvalidParam < StandardError; end

    def self.dependencies
      [:apps_handler, :app_presenter]
    end

    def inject_dependencies(dependencies)
      @app_handler       = dependencies[:apps_handler]
      @app_presenter     = dependencies[:app_presenter]
    end

    get '/v3/apps', :list
    def list
      validate_allowed_params(params)

      pagination_options = PaginationOptions.from_params(params)
      facets = params.slice('guids', 'space_guids', 'organization_guids', 'names')
      paginated_result   = @app_handler.list(pagination_options, @access_context, facets)

      [HTTP::OK, @app_presenter.present_json_list(paginated_result, facets)]
    rescue InvalidParam => e
      invalid_param!(e.message)
    end

    get '/v3/apps/:guid', :show
    def show(guid)
      app = @app_handler.show(guid, @access_context)
      app_not_found! if app.nil?

      [HTTP::OK, @app_presenter.present_json(app)]
    end

    post '/v3/apps', :create
    def create
      message = AppCreateMessage.create_from_http_request(body)
      bad_request!(message.error) if message.error

      app = @app_handler.create(message, @access_context)

      [HTTP::CREATED, @app_presenter.present_json(app)]
    rescue AppsHandler::Unauthorized
      unauthorized!
    rescue AppsHandler::InvalidApp => e
      unprocessable!(e.message)
    end

    patch '/v3/apps/:guid', :update
    def update(guid)
      message = AppUpdateMessage.create_from_http_request(guid, body)
      bad_request!(message.error) if message.error

      app = @app_handler.update(message, @access_context)
      app_not_found! if app.nil?

      [HTTP::OK, @app_presenter.present_json(app)]
    rescue AppsHandler::Unauthorized
      unauthorized!
    rescue AppsHandler::InvalidApp => e
      unprocessable!(e.message)
    end

    delete '/v3/apps/:guid', :delete
    def delete(guid)
      deleted = @app_handler.delete(guid, @access_context)
      app_not_found! unless deleted

      [HTTP::NO_CONTENT]
    rescue AppsHandler::DeleteWithProcesses
      unable_to_perform!('App deletion', 'Has child processes')
    rescue AppsHandler::Unauthorized
      app_not_found!
    end

    private

    def validate_allowed_params(params)
      schema = {
        'names' => ->(v) { v.is_a? Array },
        'guids' => ->(v) { v.is_a? Array },
        'organization_guids' => ->(v) { v.is_a? Array },
        'space_guids' => ->(v) { v.is_a? Array },
        'page' => ->(v) { v.to_i > 0 },
        'per_page' => ->(v) { v.to_i > 0 },
        'sort' => ->(v) { %w(created_at updated_at).include?(v) },
        'direction' => ->(v) { %w(asc desc).include?(v) }
      }
      params.each do |key, value|
        validator = schema[key]
        raise InvalidParam.new("Unknow query param #{key}") if validator.nil?
        raise InvalidParam.new("Invalid type for param #{key}") if !validator.call(value)
      end
    end

    def unable_to_perform!(msg, details)
      raise VCAP::Errors::ApiError.new_from_details('UnableToPerform', msg, details)
    end

    def app_not_found!
      raise VCAP::Errors::ApiError.new_from_details('ResourceNotFound', 'App not found')
    end

    def bad_request!(message)
      raise VCAP::Errors::ApiError.new_from_details('MessageParseError', message)
    end

    def unauthorized!
      raise VCAP::Errors::ApiError.new_from_details('NotAuthorized')
    end

    def unprocessable!(message)
      raise VCAP::Errors::ApiError.new_from_details('UnprocessableEntity', message)
    end

    def invalid_param!(message)
      raise VCAP::Errors::ApiError.new_from_details('BadQueryParameter', message)
    end
  end
end
