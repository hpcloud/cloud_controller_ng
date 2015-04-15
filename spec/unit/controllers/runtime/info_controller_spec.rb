require 'spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::InfoController do
    describe 'GET /v2/info' do
      it "returns a 'user' entry when authenticated" do
        get '/v2/info', {}, admin_headers
        hash = MultiJson.load(last_response.body)
        expect(hash).to have_key('user')
      end

      it "excludes the 'user' entry when not authenticated" do
        get '/v2/info', {}, {}
        hash = MultiJson.load(last_response.body)
        expect(hash).not_to have_key('user')
      end

      it 'includes data from the config' do
        get '/v2/info', {}, {}
        hash = MultiJson.load(last_response.body)
        expect(hash['name']).to eq(TestConfig.config[:info][:name])
        expect(hash['build']).to eq(TestConfig.config[:info][:build])
        expect(hash['support']).to eq(TestConfig.config[:info][:support_address])
        expect(hash['version']).to eq(TestConfig.config[:info][:version])
        expect(hash['description']).to eq(TestConfig.config[:info][:description])
        expect(hash['authorization_endpoint']).to eq(TestConfig.config[:uaa][:url])
        expect(hash['token_endpoint']).to eq(TestConfig.config[:uaa][:url])
        expect(hash['api_version']).to eq(VCAP::CloudController::Constants::API_VERSION)
      end

      it 'includes login url when configured' do
        TestConfig.override(login: { url: 'login_url' })
        get '/v2/info', {}, {}
        hash = MultiJson.load(last_response.body)
        expect(hash['authorization_endpoint']).to eq('login_url')
      end

      it 'includes the logging endpoint when configured' do
        TestConfig.override(loggregator: { url: 'loggregator_url' })
        get '/v2/info', {}, {}
        hash = MultiJson.load(last_response.body)
        expect(hash['logging_endpoint']).to eq('loggregator_url')
      end

      it 'includes cli version info when confgired' do
        TestConfig.override(info: {
          min_cli_version: 'min_cli_version',
          min_recommended_cli_version: 'min_recommended_cli_version'
        })
        get '/v2/info', {}, {}
        hash = MultiJson.load(last_response.body)
        expect(hash['min_cli_version']).to eq('min_cli_version')
        expect(hash['min_recommended_cli_version']).to eq('min_recommended_cli_version')
      end

      describe 'custom fields' do
        context 'without custom fields in config' do
          it 'does not have custom fields in the hash' do
            get '/v2/info'
            hash = MultiJson.load(last_response.body)
            expect(hash).not_to have_key('custom')
          end
        end

        context 'with custom fields in config' do
          before { TestConfig.override(info: { custom: { foo: 'bar', baz: 'foobar' } }) }

          it 'contains the custom fields' do
            get '/v2/info'

            hash = MultiJson.load(last_response.body)
            expect(hash).to have_key('custom')
            expect(hash['custom']).to eq({ 'foo' => 'bar', 'baz' => 'foobar' })
          end
        end
      end
    end
  end
end
