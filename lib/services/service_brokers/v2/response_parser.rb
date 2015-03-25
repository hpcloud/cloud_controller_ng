module VCAP::Services
  module ServiceBrokers
    module V2
      class ResponseParser
        SERVICE_BINDINGS_REGEX = %r{/v2/service_instances/[[:alnum:]-]+/service_bindings}

        def initialize(url)
          @url = url
          @logger = Steno.logger('cc.service_broker.v2.client')
        end

        def parse(method, path, response)
          case method
          when :put
            return parse_provision_or_bind(method, path, response)
          when :delete
            return parse_deprovision_or_unbind(method, path, response)
          when :get
            return parse_catalog(method, path, response)
          when :patch
            return parse_update(method, path, response)
          end
        end

        def parse_deprovision_or_unbind(method, path, response)
          unvalidated_response = UnvalidatedResponse.new(method, @url, path, response)

          validator =
          case unvalidated_response.code
          when 200
            JsonObjectValidator.new(@logger,
                SuccessValidator.new)
          when 201, 202
            JsonObjectValidator.new(@logger,
              FailingValidator.new(Errors::ServiceBrokerBadResponse))
          when 204
            SuccessValidator.new { |res| {} }
          when 202
            JsonObjectValidator.new(@logger,
              PathNotMatchValidator.new(SERVICE_BINDINGS_REGEX, Errors::ServiceBrokerBadResponse,
                StateValidator.new(['in progress'],
                  SuccessValidator.new)))
          when 410
            @logger.warn("Already deleted: #{unvalidated_response.uri}")
            SuccessValidator.new { |res| nil }
          else
            FailingValidator.new(Errors::ServiceBrokerBadResponse)
          end

          validator = CommonErrorValidator.new(validator)
          validator.validate(unvalidated_response.to_hash)
        end

        def parse_provision_or_bind(method, path, response)
          unvalidated_response = UnvalidatedResponse.new(method, @url, path, response)

          validator =
          case unvalidated_response.code
          when 200
            JsonObjectValidator.new(@logger,
              StateValidator.new(['succeeded', 'failed', 'in progress', nil],
                SuccessValidator.new))
          when 201
            JsonObjectValidator.new(@logger,
              StateValidator.new(['succeeded', nil],
                SuccessValidator.new))
          when 202
            JsonObjectValidator.new(@logger,
              PathNotMatchValidator.new(SERVICE_BINDINGS_REGEX, Errors::ServiceBrokerBadResponse,
                StateValidator.new(['in progress'],
                  SuccessValidator.new)))
          when 409
            FailingValidator.new(Errors::ServiceBrokerConflict)
          when 422
            FailWhenValidator.new('error', ['AsyncRequired'], Errors::AsyncRequired,
              FailingValidator.new(Errors::ServiceBrokerBadResponse))
          else
            FailingValidator.new(Errors::ServiceBrokerBadResponse)
          end

          validator = CommonErrorValidator.new(validator)
          validator.validate(unvalidated_response.to_hash)
        end

        def parse_catalog(method, path, response)
          unvalidated_response = UnvalidatedResponse.new(method, @url, path, response)

          validator =
          case unvalidated_response.code
          when 200
            JsonObjectValidator.new(@logger, SuccessValidator.new)
          when 201, 202
            JsonObjectValidator.new(@logger,
              FailingValidator.new(Errors::ServiceBrokerBadResponse))
          else
            FailingValidator.new(Errors::ServiceBrokerBadResponse)
          end

          validator = CommonErrorValidator.new(validator)
          validator.validate(unvalidated_response.to_hash)
        end

        def parse_update(method, path, response)
          unvalidated_response = UnvalidatedResponse.new(method, @url, path, response)

          validator =
          case unvalidated_response.code
          when 200, 202
            JsonObjectValidator.new(@logger,
                SuccessValidator.new)
          when 422
            FailWhenValidator.new('error', ['AsyncRequired'], Errors::AsyncRequired,
              FailingValidator.new(Errors::ServiceBrokerRequestRejected))
          when 201
            JsonObjectValidator.new(@logger,
              FailingValidator.new(Errors::ServiceBrokerBadResponse))
          else
            FailingValidator.new(Errors::ServiceBrokerBadResponse)
          end

          validator = CommonErrorValidator.new(validator)
          validator.validate(unvalidated_response.to_hash)
        end

        def parse_fetch_state(method, path, response)
          unvalidated_response = UnvalidatedResponse.new(method, @url, path, response)

          validator =
          case unvalidated_response.code
          when 200
            JsonObjectValidator.new(@logger,
              StateValidator.new(['succeeded', 'failed', 'in progress'],
                SuccessValidator.new))
          when 201, 202
            JsonObjectValidator.new(@logger,
              FailingValidator.new(Errors::ServiceBrokerBadResponse))
          else
            FailingValidator.new(Errors::ServiceBrokerBadResponse)
          end

          validator = CommonErrorValidator.new(validator)
          validator.validate(unvalidated_response.to_hash)
        end

        class UnvalidatedResponse
          attr_reader :code, :uri

          def initialize(method, uri, path, response)
            @method = method
            @code = response.code.to_i
            @uri = URI(uri + path)
            @response = response
          end

          def body
            response.body
          end

          def to_hash
            {
              method: @method,
              uri: @uri,
              code: @code,
              response: @response,
            }
          end
        end

        class PathNotMatchValidator
          def initialize(path_regex, error_class, validator)
            @path_regex = path_regex
            @error_class = error_class
            @validator = validator
          end

          def validate(method:, uri:, code:, response:)
            if @path_regex.match(uri.to_s)
              raise @error_class.new(uri.to_s, method, response)
            else
              @validator.validate(method: method, uri: uri, code: code, response: response)
            end
          end
        end

        class FailWhenValidator
          def initialize(key, values, error_class, validator)
            @key = key
            @values = values
            @error_class = error_class
            @validator = validator
          end

          def validate(method:, uri:, code:, response:)
            begin
              parsed_response = MultiJson.load(response.body)
            rescue MultiJson::ParseError
              @validator.validate(method: method, uri: uri, code: code, response: response)
              return
            end

            if @values.include?(parsed_response[@key])
              raise @error_class.new(uri.to_s, method, response)
            else
              @validator.validate(method: method, uri: uri, code: code, response: response)
            end
          end
        end

        class SuccessValidator
          def initialize(&block)
            if block_given?
              @processor = block
            else
              @processor = ->(response) { MultiJson.load(response.body) }
            end
          end

          def validate(method:, uri:, code:, response:)
            @processor.call(response)
          end
        end

        class FailingValidator
          def initialize(error_class)
            @error_class = error_class
          end

          def validate(method:, uri:, code:, response:)
            raise @error_class.new(uri.to_s, method, response)
          end
        end

        class JsonObjectValidator
          def initialize(logger, validator)
            @logger = logger
            @validator = validator
          end

          def validate(method:, uri:, code:, response:)
            begin
              parsed_response = MultiJson.load(response.body)
            rescue MultiJson::ParseError
              @logger.warn("MultiJson parse error `#{response.try(:body).inspect}'")
            end

            unless parsed_response.is_a?(Hash)
              raise Errors::ServiceBrokerResponseMalformed.new(uri, @method, response)
            end

            @validator.validate(method: method, uri: uri, code: code, response: response)
          end
        end

        class StateValidator
          def initialize(valid_states, validator)
            @valid_states = valid_states
            @validator = validator
          end

          def validate(method:, uri:, code:, response:)
            parsed_response = MultiJson.load(response.body)
            if @valid_states.include?(state_from_parsed_response(parsed_response))
              @validator.validate(method: method, uri: uri, code: code, response: response)
            else
              raise Errors::ServiceBrokerResponseMalformed.new(uri.to_s, @method, response)
            end
          end

          private

          def state_from_parsed_response(parsed_response)
            parsed_response ||= {}
            last_operation = parsed_response['last_operation'] || {}
            last_operation['state']
          end
        end

        class CommonErrorValidator
          def initialize(validator)
            @validator = validator
          end

          def validate(method:, uri:, code:, response:)
            case code
            when 401
              raise Errors::ServiceBrokerApiAuthenticationFailed.new(uri.to_s, method, response)
            when 408
              raise Errors::ServiceBrokerApiTimeout.new(uri.to_s, method, response)
            when 409, 410, 422
            when 400..499
              raise Errors::ServiceBrokerRequestRejected.new(uri.to_s, method, response)
            when 500..599
              raise Errors::ServiceBrokerBadResponse.new(uri.to_s, method, response)
            end
            @validator.validate(method: method, uri: uri, code: code, response: response)
          end
        end
      end
    end
  end
end
