require 'spec_helper'
require 'yajl'

module VCAP::CloudController
  # Test /v2/info overrides

  describe VCAP::CloudController::InfoController, type: :controller do
    let(:current_user) { make_user_with_default_space(:admin => true) }
    let(:headers) { headers_for(current_user) }

    it 'should ignore use of nginx' do
      TestConfig.override(:nginx => { :use_nginx => true })
      # Setting kato config should trigger the override hook
      Kato::Config.set 'cloud_controller_ng', 'nginx/use_nginx', true

      get '/v2/info', {}, headers
      expect(last_response.status).to eq(200)
      hash = Yajl::Parser.parse(last_response.body)

      expect(hash).to have_key('stackato')
      expect(hash['stackato']).to have_key('cc_nginx')
      expect(hash['stackato']['cc_nginx']).to be_falsey

    end
  end
end
