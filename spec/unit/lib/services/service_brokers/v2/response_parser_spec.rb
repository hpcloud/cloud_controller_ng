require 'spec_helper'

module VCAP::Services
  module ServiceBrokers
    module V2
      describe 'ResponseParser' do
        def get_method_and_path(operation)
          case operation
          when :provision
            method = :parse_provision_or_bind
            path = '/v2/service_instances/GUID'
          when :deprovision
            method = :parse_deprovision_or_unbind
            path = '/v2/service_instances/GUID'
          when :update
            method = :parse_update
            path = '/v2/service_instances/GUID'
          when :bind
            method = :parse_provision_or_bind
            path = '/v2/service_instances/GUID/service_bindings/BINDING_GUID'
          when :unbind
            method = :parse_deprovision_or_unbind
            path = '/v2/service_instances/GUID/service_bindings/BINDING_GUID'
          when :fetch_state
            method = :parse_fetch_state
            path = '/v2/service_instances/GUID'
          when :fetch_catalog
            method = :parse_catalog
            path = '/v2/catalog'
          end

          [method, path]
        end

        def self.test_common_error_cases(operation)
          test_case(operation, 302, broker_partial_json,   error: Errors::ServiceBrokerBadResponse)
          test_case(operation, 302, broker_malformed_json, error: Errors::ServiceBrokerBadResponse)
          test_case(operation, 302, broker_empty_json,     error: Errors::ServiceBrokerBadResponse)
          test_case(operation, 401, broker_partial_json,   error: Errors::ServiceBrokerApiAuthenticationFailed)
          test_case(operation, 401, broker_malformed_json, error: Errors::ServiceBrokerApiAuthenticationFailed)
          test_case(operation, 401, broker_empty_json,     error: Errors::ServiceBrokerApiAuthenticationFailed)
          test_case(operation, 404, broker_partial_json,   error: Errors::ServiceBrokerRequestRejected)
          test_case(operation, 404, broker_malformed_json, error: Errors::ServiceBrokerRequestRejected)
          test_case(operation, 404, broker_empty_json,     error: Errors::ServiceBrokerRequestRejected)
          test_case(operation, 500, broker_partial_json,   error: Errors::ServiceBrokerBadResponse)
          test_case(operation, 500, broker_malformed_json, error: Errors::ServiceBrokerBadResponse)
          test_case(operation, 500, broker_empty_json,     error: Errors::ServiceBrokerBadResponse)
        end

        def self.test_pass_through(operation, status, with_body={}, expected_state:)
          response_body = with_additional_field
          response_body.merge!(with_body)

          # We expect to pass thru all params except 'state', which gets placed in the last_operation section
          expected_client_result = client_result_with_state(expected_state).merge(response_body.except('state'))
          test_case(operation, status, response_body.to_json, result: expected_client_result)
        end

        def self.test_case(operation, code, body, opts={})
          expect_warning = !!opts[:expect_warning]
          description = opts[:description]
          result = opts[:result]
          error = opts[:error]

          context "making a #{operation} request that returns code #{code} and body #{body}" do
            let(:response_parser) { ResponseParser.new('service-broker.com') }
            let(:fake_response) { instance_double(VCAP::Services::ServiceBrokers::V2::HttpResponse) }
            let(:body) { body }
            let(:logger) { instance_double(Steno::Logger, warn: nil) }

            before do
              @method, @path = get_method_and_path(operation)
              allow(fake_response).to receive(:code).and_return(code)
              allow(fake_response).to receive(:body).and_return(body)
              allow(fake_response).to receive(:message).and_return('message')
              allow(Steno).to receive(:logger).and_return(logger)
            end

            if error
              it "raises a #{error} error" do
                expect { response_parser.send(@method, @path, fake_response) }.to raise_error(error) do |e|
                  expect(e.to_h['description']).to eq(description) if description
                end
                expect(logger).to have_received(:warn) if expect_warning
              end
            else
              it 'returns the parsed response' do
                expect(response_parser.send(@method, @path, fake_response)).to eq(result)
              end
            end
          end
        end

        def self.broker_partial_json
          '""'
        end

        def self.broker_malformed_json
          'shenanigans'
        end

        def self.broker_empty_json
          '{}'
        end

        def self.broker_non_empty_json
          {
            'last_operation' => {
              'state' => 'foobar',
              'random' => 'pants'
            }
          }.to_json
        end

        def self.broker_body_with_state(state)
          {
            'state' => state,
          }
        end

        def self.with_dashboard_url
          {
            'dashboard_url' => 'url.com/foo'
          }
        end

        def self.with_additional_field
          {
            'foo' => 'bar'
          }
        end

        def self.valid_catalog
          {
            'services' => [
              {
                'id' => '12345',
                'name' => 'valid service name',
                'description' => 'valid service description',
                'plans' => [
                  {
                    'id' => 'valid plan guid',
                    'name' => 'valid plan name',
                    'description' => 'plan description'
                  }
                ]
              }
            ]
          }
        end

        def self.client_result_with_state(state, description: nil)
          response_body = {
            'last_operation' => {
              'state' => state,
            }
          }

          response_body['last_operation']['description'] = description if description
          response_body
        end

        def self.response_not_understood(expected_state, actual_state)
          actual_state = (actual_state) ? "'#{actual_state}'" : 'null'
          'The service broker returned an invalid response for the request to service-broker.com/v2/service_instances/GUID: ' + \
          "expected state was '#{expected_state}', broker returned #{actual_state}."
        end

        def self.invalid_json_error(body)
          'The service broker returned an invalid response for the request to service-broker.com/v2/service_instances/GUID: ' + \
          "expected valid JSON object in body, broker returned '#{body}'"
        end

        def self.broker_returned_an_error(status, body)
          'The service broker returned an invalid response for the request to service-broker.com/v2/service_instances/GUID. ' + \
          "Status Code: #{status} message, Body: #{body}"
        end

        # rubocop:disable Metrics/LineLength
        test_case(:provision, 200, broker_partial_json,                              error: Errors::ServiceBrokerResponseMalformed, description: invalid_json_error(broker_partial_json))
        test_case(:provision, 200, broker_malformed_json,                            error: Errors::ServiceBrokerResponseMalformed, expect_warning: true, description: invalid_json_error(broker_malformed_json))
        test_case(:provision, 200, broker_empty_json,                                result: client_result_with_state('succeeded'))
        test_case(:provision, 200, with_dashboard_url.to_json,                result: client_result_with_state('succeeded').merge(with_dashboard_url))
        test_case(:provision, 201, broker_partial_json,                              error: Errors::ServiceBrokerResponseMalformed, description: invalid_json_error(broker_partial_json))
        test_case(:provision, 201, broker_malformed_json,                            error: Errors::ServiceBrokerResponseMalformed, expect_warning: true, description: invalid_json_error(broker_malformed_json))
        test_case(:provision, 201, broker_empty_json,                                result: client_result_with_state('succeeded'))
        test_case(:provision, 201, with_dashboard_url.to_json,                result: client_result_with_state('succeeded').merge(with_dashboard_url))
        test_case(:provision, 202, broker_partial_json,                              error: Errors::ServiceBrokerResponseMalformed, description: invalid_json_error(broker_partial_json))
        test_case(:provision, 202, broker_malformed_json,                            error: Errors::ServiceBrokerResponseMalformed, expect_warning: true, description: invalid_json_error(broker_malformed_json))
        test_case(:provision, 202, broker_empty_json,                                result: client_result_with_state('in progress'))
        test_case(:provision, 202, broker_non_empty_json,                            result: client_result_with_state('in progress'))
        test_case(:provision, 202, with_dashboard_url.to_json,                result: client_result_with_state('in progress').merge(with_dashboard_url))
        test_case(:bind,      202, broker_empty_json,                                error: Errors::ServiceBrokerBadResponse)
        test_case(:provision, 204, broker_partial_json,                              error: Errors::ServiceBrokerBadResponse)
        test_case(:provision, 204, broker_malformed_json,                            error: Errors::ServiceBrokerBadResponse)
        test_case(:provision, 204, broker_empty_json,                                error: Errors::ServiceBrokerBadResponse)
        test_case(:provision, 409, broker_partial_json,                              error: Errors::ServiceBrokerConflict)
        test_case(:provision, 409, broker_malformed_json,                            error: Errors::ServiceBrokerConflict)
        test_case(:provision, 409, broker_empty_json,                                error: Errors::ServiceBrokerConflict)
        test_case(:provision, 410, broker_partial_json,                              error: Errors::ServiceBrokerBadResponse)
        test_case(:provision, 410, broker_malformed_json,                            error: Errors::ServiceBrokerBadResponse)
        test_case(:provision, 410, broker_empty_json,                                error: Errors::ServiceBrokerBadResponse)
        test_case(:provision, 422, broker_partial_json,                              error: Errors::ServiceBrokerBadResponse)
        test_case(:provision, 422, broker_malformed_json,                            error: Errors::ServiceBrokerBadResponse)
        test_case(:provision, 422, broker_empty_json,                                error: Errors::ServiceBrokerBadResponse)
        test_case(:provision, 422, { error: 'AsyncRequired' }.to_json,               error: Errors::AsyncRequired)
        test_case(:bind,      422, { error: 'AsyncRequired' }.to_json,               error: Errors::AsyncRequired)
        test_case(:provision, 422, { error: 'RequiresApp' }.to_json,                 error: Errors::ServiceBrokerBadResponse)
        test_case(:bind,      422, { error: 'RequiresApp' }.to_json,                 error: Errors::AppRequired)
        test_common_error_cases(:provision)

        test_case(:fetch_state, 200, broker_partial_json,                            error: Errors::ServiceBrokerResponseMalformed, description: invalid_json_error(broker_partial_json))
        test_case(:fetch_state, 200, broker_malformed_json,                          error: Errors::ServiceBrokerResponseMalformed, description: invalid_json_error(broker_malformed_json), expect_warning: true)
        test_case(:fetch_state, 200, broker_empty_json,                              error: Errors::ServiceBrokerResponseMalformed, description: response_not_understood('succeeded', ''))
        test_case(:fetch_state, 200, broker_body_with_state('unrecognized').to_json, error: Errors::ServiceBrokerResponseMalformed, description: response_not_understood('succeeded', 'unrecognized'))
        test_case(:fetch_state, 200, broker_body_with_state('succeeded').to_json,    result: client_result_with_state('succeeded'))
        test_case(:fetch_state, 200, broker_body_with_state('succeeded').merge('description' => 'a description').to_json,    result: client_result_with_state('succeeded', description: 'a description'))
        test_pass_through(:fetch_state, 200, broker_body_with_state('succeeded'),    expected_state: 'succeeded')
        test_case(:fetch_state, 201, broker_partial_json,                            error: Errors::ServiceBrokerResponseMalformed)
        test_case(:fetch_state, 201, broker_malformed_json,                          error: Errors::ServiceBrokerResponseMalformed)
        test_case(:fetch_state, 201, broker_body_with_state('succeeded').to_json,    error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_state, 202, broker_partial_json,                            error: Errors::ServiceBrokerResponseMalformed)
        test_case(:fetch_state, 202, broker_malformed_json,                          error: Errors::ServiceBrokerResponseMalformed)
        test_case(:fetch_state, 202, broker_body_with_state('succeeded').to_json,    error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_state, 204, broker_partial_json,                            error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_state, 204, broker_malformed_json,                          error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_state, 204, broker_empty_json,                              error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_state, 409, broker_partial_json,                            error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_state, 409, broker_malformed_json,                          error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_state, 409, broker_empty_json,                              error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_state, 410, broker_empty_json,                              result: {})
        test_case(:fetch_state, 410, broker_partial_json,                            result: {})
        test_case(:fetch_state, 410, broker_malformed_json,                          result: {})
        test_case(:fetch_state, 422, broker_partial_json,                            error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_state, 422, broker_malformed_json,                          error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_state, 422, broker_empty_json,                              error: Errors::ServiceBrokerBadResponse)
        test_common_error_cases(:fetch_state)

        test_case(:fetch_catalog, 200, broker_partial_json,                          error: Errors::ServiceBrokerResponseMalformed)
        test_case(:fetch_catalog, 200, broker_malformed_json,                        error: Errors::ServiceBrokerResponseMalformed)
        test_case(:fetch_catalog, 200, broker_empty_json,                            result: {})
        test_case(:fetch_catalog, 200, valid_catalog.to_json,                 result: valid_catalog)
        test_case(:fetch_catalog, 201, broker_partial_json,                          error: Errors::ServiceBrokerResponseMalformed)
        test_case(:fetch_catalog, 201, broker_malformed_json,                        error: Errors::ServiceBrokerResponseMalformed)
        test_case(:fetch_catalog, 201, broker_empty_json,                            error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_catalog, 201, valid_catalog.to_json,                 error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_catalog, 204, broker_partial_json,                          error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_catalog, 204, broker_malformed_json,                        error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_catalog, 204, broker_empty_json,                            error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_catalog, 204, valid_catalog.to_json,                 error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_catalog, 409, broker_partial_json,                          error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_catalog, 409, broker_malformed_json,                        error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_catalog, 409, broker_empty_json,                            error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_catalog, 410, broker_partial_json,                          error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_catalog, 410, broker_malformed_json,                        error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_catalog, 410, broker_empty_json,                            error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_catalog, 422, broker_partial_json,                          error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_catalog, 422, broker_malformed_json,                        error: Errors::ServiceBrokerBadResponse)
        test_case(:fetch_catalog, 422, broker_empty_json,                            error: Errors::ServiceBrokerBadResponse)
        test_common_error_cases(:fetch_catalog)

        test_case(:deprovision, 200, broker_partial_json,                            error: Errors::ServiceBrokerResponseMalformed, description: invalid_json_error(broker_partial_json))
        test_case(:deprovision, 200, broker_malformed_json,                          error: Errors::ServiceBrokerResponseMalformed, expect_warning: true, description: invalid_json_error(broker_malformed_json))
        test_case(:deprovision, 200, broker_empty_json,                              result: client_result_with_state('succeeded'))
        test_pass_through(:deprovision, 200,                                  expected_state: 'succeeded')
        test_case(:deprovision, 201, broker_partial_json,                            error: Errors::ServiceBrokerBadResponse, description: broker_returned_an_error(201, broker_partial_json))
        test_case(:deprovision, 201, broker_malformed_json,                          error: Errors::ServiceBrokerBadResponse, description: broker_returned_an_error(201, broker_malformed_json))
        test_case(:deprovision, 201, broker_empty_json,                              error: Errors::ServiceBrokerBadResponse, description: broker_returned_an_error(201, broker_empty_json))
        test_case(:deprovision, 201, { description: 'error' }.to_json,        error: Errors::ServiceBrokerBadResponse, description: broker_returned_an_error(201, { description: 'error' }.to_json))
        test_case(:deprovision, 202, broker_partial_json,                            error: Errors::ServiceBrokerResponseMalformed, description: invalid_json_error(broker_partial_json))
        test_case(:deprovision, 202, broker_malformed_json,                          error: Errors::ServiceBrokerResponseMalformed, expect_warning: true, description: invalid_json_error(broker_malformed_json))
        test_case(:deprovision, 202, broker_empty_json,                              result: client_result_with_state('in progress'))
        test_case(:deprovision, 202, broker_non_empty_json,                          result: client_result_with_state('in progress'))
        test_pass_through(:deprovision, 202,                                  expected_state: 'in progress')
        test_case(:unbind,      202, broker_empty_json,                              error: Errors::ServiceBrokerBadResponse)
        test_case(:unbind,      204, broker_empty_json,                              error: Errors::ServiceBrokerBadResponse)
        test_case(:unbind,      204, broker_partial_json,                              error: Errors::ServiceBrokerBadResponse)
        test_case(:unbind,      204, broker_malformed_json,                              error: Errors::ServiceBrokerBadResponse)
        test_case(:deprovision, 204, broker_partial_json,                            error: Errors::ServiceBrokerBadResponse)
        test_case(:deprovision, 204, broker_malformed_json,                          error: Errors::ServiceBrokerBadResponse)
        test_case(:deprovision, 204, broker_empty_json,                              error: Errors::ServiceBrokerBadResponse)
        test_case(:deprovision, 409, broker_partial_json,                            error: Errors::ServiceBrokerBadResponse)
        test_case(:deprovision, 409, broker_malformed_json,                          error: Errors::ServiceBrokerBadResponse)
        test_case(:deprovision, 410, broker_empty_json,                              result: {})
        test_case(:deprovision, 410, broker_partial_json,                            result: {})
        test_case(:deprovision, 410, broker_malformed_json,                          result: {})
        test_case(:deprovision, 422, broker_empty_json,                              error: Errors::ServiceBrokerBadResponse)
        test_case(:deprovision, 422, broker_partial_json,                            error: Errors::ServiceBrokerBadResponse)
        test_case(:deprovision, 422, broker_malformed_json,                          error: Errors::ServiceBrokerBadResponse)
        test_case(:deprovision, 422, { error: 'AsyncRequired' }.to_json,      error: Errors::AsyncRequired)
        test_common_error_cases(:deprovision)

        test_case(:update, 200, broker_partial_json,                                 error: Errors::ServiceBrokerResponseMalformed, description: invalid_json_error(broker_partial_json))
        test_case(:update, 200, broker_malformed_json,                               error: Errors::ServiceBrokerResponseMalformed, expect_warning: true, description: invalid_json_error(broker_malformed_json))
        test_case(:update, 200, broker_empty_json,                                   result: client_result_with_state('succeeded'))
        test_pass_through(:update, 200,                                       expected_state: 'succeeded')
        test_case(:update, 201, broker_partial_json,                                 error: Errors::ServiceBrokerBadResponse, description: broker_returned_an_error(201, broker_partial_json))
        test_case(:update, 201, broker_malformed_json,                               error: Errors::ServiceBrokerBadResponse, description: broker_returned_an_error(201, broker_malformed_json))
        test_case(:update, 201, broker_empty_json,                                   error: Errors::ServiceBrokerBadResponse, description: broker_returned_an_error(201, broker_empty_json))
        test_case(:update, 201, { 'foo' => 'bar' }.to_json,                   error: Errors::ServiceBrokerBadResponse, description: broker_returned_an_error(201, { 'foo' => 'bar' }.to_json))
        test_case(:update, 202, broker_partial_json,                                 error: Errors::ServiceBrokerResponseMalformed, description: invalid_json_error(broker_partial_json))
        test_case(:update, 202, broker_malformed_json,                               error: Errors::ServiceBrokerResponseMalformed, expect_warning: true, description: invalid_json_error(broker_malformed_json))
        test_case(:update, 202, broker_empty_json,                                   result: client_result_with_state('in progress'))
        test_case(:update, 202, broker_non_empty_json,                               result: client_result_with_state('in progress'))
        test_pass_through(:update, 202,                                       expected_state: 'in progress')
        test_case(:update, 204, broker_partial_json,                                 error: Errors::ServiceBrokerBadResponse)
        test_case(:update, 204, broker_malformed_json,                               error: Errors::ServiceBrokerBadResponse)
        test_case(:update, 204, broker_empty_json,                                   error: Errors::ServiceBrokerBadResponse)
        test_case(:update, 409, broker_empty_json,                                   error: Errors::ServiceBrokerBadResponse)
        test_case(:update, 409, broker_partial_json,                                 error: Errors::ServiceBrokerBadResponse)
        test_case(:update, 410, broker_empty_json,                                   error: Errors::ServiceBrokerBadResponse)
        test_case(:update, 410, broker_partial_json,                                 error: Errors::ServiceBrokerBadResponse)
        test_case(:update, 422, broker_empty_json,                                   error: Errors::ServiceBrokerRequestRejected)
        test_case(:update, 422, broker_partial_json,                                 error: Errors::ServiceBrokerRequestRejected)
        test_case(:update, 422, { error: 'AsyncRequired' }.to_json,           error: Errors::AsyncRequired)
        test_common_error_cases(:update)
        # rubocop:enable Metrics/LineLength
      end
    end
  end
end
