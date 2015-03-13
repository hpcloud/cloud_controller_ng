module UAARequests
  def self.stub_all
    # stub token request
    WebMock::API.stub_request(:post, "http://cc-service-dashboards:some-sekret@localhost:8080/uaa/oauth/token").to_return(
      status:  200,
      body:    { token_type: "token-type", access_token: "access-token" }.to_json,
      headers: { "content-type" => "application/json" })

    # stub client search request
    WebMock::API.stub_request(:get, "http://localhost:8080/uaa/oauth/clients/dash-id").to_return(status: 404)

    # stub client create request
    WebMock::API.stub_request(:post, "http://localhost:8080/uaa/oauth/clients/tx/modify").to_return(
      status:  201,
      body:    { id: "some-id", client_id: "dash-id" }.to_json,
      headers: { "content-type" => "application/json" })


    # stubbing requests for stackato scim 

    WebMock::API.stub_request(:post, "http://cloud_controller:@localhost:8080/uaa/oauth/token").
      to_return(
        :status => 200, 
        :body => { token_type: "token-type", access_token: "access-token" }.to_json,
        :headers => { "content-type" => "application/json" })


    WebMock::API.stub_request(:get, %r"http://localhost:8080/uaa/Users/uaa-id-\d+").
      to_return(
        :status => 200, 
        :body => { username: "testuser" }.to_json,
        :headers => { "content-type" => "application/json" })

    # security_context_configurer_spec.rb
    WebMock::API.stub_request(:get, %r"http://localhost:8080/uaa/Users/user-id-\d+").
      with(:headers => {'Accept'=>'application/json;charset=utf-8',
             'Authorization'=>'token-type access-token',
             'User-Agent'=>'Ruby'}).
      to_return(
        :status => 200, 
        :body => "",
        :headers => {})

    WebMock::API.stub_request(:delete, %r"http://localhost:8080/uaa/oauth/clients/host-\d+(?:\.test|\.domain-\d+)?.example.com-[-\da-f]{36}\z").
      with(:headers => {'Accept'=>'*/*',
             'Authorization'=>'token-type access-token',
             'User-Agent'=>'Ruby'}).
      to_return(
        :status => 200, 
        :body => "",
        :headers => {})

    WebMock::API.stub_request(:delete, %r"http://localhost:8080/uaa/oauth/clients/host-\d+\.domain-\d+\.example\.com-[-a-f0-9]{36}\z").
      with(:headers => {'Accept'=>'*/*', 'Authorization'=>'token-type access-token', 'User-Agent'=>'Ruby'}).
      to_return(:status => 200, :body => "", :headers => {})


    WebMock::API.stub_request(:delete, %r"http://localhost:8080/uaa/oauth/clients/host-\d+.test.example.com-[-\da-f]{36}\z").
      with(:headers => {'Accept'=>'*/*',
             'Authorization'=>'token-type access-token',
             'User-Agent'=>'Ruby'}).
      to_return(
        :status => 200, 
        :body => "",
        :headers => {})

    # stubs suggested by tests run on jenkins:
    # controllers/services/service_brokers_controller_spec.rb:165
    WebMock::API.stub_request(:delete, %r"http://cloud_controller:@localhost:8080/uaa/check_token").
      with(:body => "token_type_hint=access_token&token=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjoidWFhLWlkLTEwIiwiZW1haWwiOiJlbWFpbC0xQHNvbWVkb21haW4uY29tIiwic2NvcGUiOlsiY2xvdWRfY29udHJvbGxlci5hZG1pbiJdLCJhdWQiOlsiY2xvdWRfY29udHJvbGxlciJdLCJleHAiOjE0MjY4ODI0MDJ9.mkS66scnqi1GN2EMIIy60ue-zP0FyWRoJSixEU8cD04",
           :headers => {'Accept'=>'application/json;charset=utf-8',
             'Content-Length'=>'296',
             'User-Agent'=>'Ruby'}).
      to_return(
        :status => 200, 
        :body => "",
        :headers => {})

    # controllers/services/service_brokers_controller_spec.rb:174
    WebMock::API.stub_request(:post, %r"http://cloud_controller:@localhost:8080/uaa/check_token").
      with(:body => %r"token_type_hint=access_token\&token=[-\w.]+",
           :headers => {'Accept'=>'application/json;charset=utf-8',
             'Content-Length'=>/\d+/,  # 296 ? 328 - who cares...
             'User-Agent'=>'Ruby'}).
      to_return(
        :status => 200, 
        :body => "",
        :headers => {})

  end
end
