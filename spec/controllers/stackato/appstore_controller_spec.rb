require "spec_helper"
require "stackato/spec_helper"
require "steno"
require "controllers/stackato/appstore_controller"

describe VCAP::CloudController::StackatoAppStoreControllerController do


  let(:steno_config) { Steno::Config.new(:sinks   => [Steno::Sink::IO.for_file("/dev/null")], 
                                         :codec   => Steno::Codec::Json.new,
                                         :context => Steno::Context::ThreadLocal.new) }
  let(:logger) { Steno.init(steno_config)
                 Steno.logger("test") }
  let(:controller) {  
    allow_any_instance_of(VCAP::CloudController::RestController::ModelController).to receive( 
      :inject_dependencies ) { nil }
    VCAP::CloudController::StackatoAppStoreControllerController.new( {}, logger, {}, {}, nil ) 
  }

  describe :app_create do
    context 'when called with valid params' do
      it 'should respond with an app guid' do
        allow(Yajl::Parser).to receive(:parse) { {"space_guid" => "foo",
                                                  "app_name" => "bar"} }
        allow(controller).to receive(:invoke_api) { {"GUID" => "foo"} }
        expect(controller.app_create()).to include( "app_guid", "foo" )
      end

      it 'should call /create' do
        allow(Yajl::Parser).to receive(:parse) { {"space_guid" => "foo",
                                                  "app_name" => "bar"} }
        allow(controller).to receive(:invoke_api) { {"GUID" => "foo"} }
        expect(controller).to receive(:invoke_api).with("/create", anything)
        controller.app_create()
      end
    end

    context 'when called with invalid params' do
      it 'should fail' do
        allow(Yajl::Parser).to receive(:parse) { {"foo" => "bar"} }
        expect{controller.app_create()}.to raise_error Errors::ApiError
      end
    end

    context 'when called with an invalid app name' do
      it 'should fail' do
        allow(Yajl::Parser).to receive(:parse) { {"space_guid" => "foo",
                                                  "app_name" => "$$"} }
        expect{controller.app_create()}.to raise_error Errors::ApiError
      end
    end
  end

  describe :app_deploy do
    context 'when called with valid params' do
      it 'should respond with an app guid' do
        app_info = double()
        allow(app_info).to receive(:guid) { "foo" }
        allow(controller).to receive(:find_guid_and_validate_access) { app_info }

        allow(Yajl::Parser).to receive(:parse) { {"space_guid" => "foo",
                                                  "app_name" => "bar",
                                                  "from" => "baz"} }
        allow(controller).to receive(:invoke_api) { {"GUID" => "foo"} }

        expect(controller.app_deploy("foo")).to include( "GUID", "foo" )
      end

      it 'should call /push' do
        app_info = double()
        allow(app_info).to receive(:guid) { "foo" }
        allow(controller).to receive(:find_guid_and_validate_access) { app_info }

        allow(Yajl::Parser).to receive(:parse) { {"space_guid" => "foo",
                                                  "app_name" => "bar",
                                                  "from" => "baz"} }
        allow(controller).to receive(:invoke_api) { {"GUID" => "foo"} }
        expect(controller).to receive(:invoke_api).with("/push", anything)

        controller.app_deploy("foo")
      end
    end

    context 'when called with invalid params' do
      it 'should fail' do
        allow(Yajl::Parser).to receive(:parse) { {"foo" => "bar"} }
        expect{controller.app_deploy("foo")}.to raise_error Errors::ApiError
      end
    end

    context 'when called with an invalid app name' do
      it 'should fail' do
        allow(Yajl::Parser).to receive(:parse) { {"space_guid" => "foo",
                                                  "app_name" => "$$",
                                                  "from" => "baz"} }
        expect{controller.app_deploy("foo")}.to raise_error Errors::ApiError
      end
    end
  end

  describe :ensure_params do
    context 'called with a valid keys' do
      it 'should be successful' do
        param = 'foo'
        expect(
          controller.ensure_params({ param => 'bar' }, [param])
        ).to eq([param])
      end
    end

    context 'called with an invalid path' do
      it 'should raise an error' do
        expect{
          controller.ensure_params({:foo=>'bar'}, ['baz'])
        }.to raise_error Errors::ApiError
      end
    end
  end

  describe :validate_app_name do
    context 'called with a valid name' do
      it 'should accept the valid name' do
        expect(
          controller.validate_app_name('1234')
        ).to eq(nil)
      end
    end

    context 'called with an invalid name' do
      it 'should reject an invalid name' do
        expect{
          controller.validate_app_name('$$')
        }.to raise_error Errors::ApiError
      end
    end
  end

  describe :set_app_deploy_defaults do
    let(:empty_params)   { Hash.new }
    let(:git_params)     { { 'type' => 'git' } }
    let(:type_params)    { { 'type' => 'foo' } }
    let(:astrue_params)  { { 'autostart' => true } }
    let(:asfalse_params) { { 'autostart' => false } }

    context 'called without autostart' do
      it 'should set autostart to true' do
        expect( controller.set_app_deploy_defaults( empty_params ) ).to include( 'autostart' => true )
      end
    end

    context 'should not modify autostart' do
      it 'when autostart is true' do
        expect( controller.set_app_deploy_defaults( astrue_params ) ).to include( 'autostart' => true )
      end

      it 'when autostart is false' do
        expect( controller.set_app_deploy_defaults( asfalse_params ) ).to include( 'autostart' => false )
      end
    end

    context 'called with an empty type' do
      it 'should set the type to "git"' do
        expect( controller.set_app_deploy_defaults( empty_params ) ).to include( 'type' => 'git' )
      end
    end

    context 'called with a type' do
      it 'should not modify the type' do
        expect( controller.set_app_deploy_defaults( type_params ) ).to include( 'type' => 'foo' )
      end
    end
  end

  describe :invoke_api do
    context 'called with a valid path' do
      it 'should work' do
        allow(controller).to receive(:http_post_json) { [200, '{ "hello": "world" }'] }
        expect{ controller.invoke_api( "/create", "" ) }.not_to raise_error 
      end
    end

    context 'called with an invalid path' do
      it 'should raise an error' do
        allow(controller).to receive(:http_post_json) { [400, '{ "hello": "world" }'] }
        expect{ controller.invoke_api( "/create", "" ) }.to raise_error Errors::ApiError
      end
    end
  end

  describe :http_post_json do
    context 'called with a valid path' do
      it 'should receive a valid return code' do
        stub_request(:post, "http://127.0.0.1/").
          with(:body => "\"foo=1\"",
               :headers => {'Accept'=>'*/*', 
                            'Content-Type'=>'application/json', 
                            'User-Agent'=>'Ruby'}).
          to_return(:status => 200, :body => "", :headers => {})
        expect( controller.http_post_json( "http://127.0.0.1", "foo=1" ) ).to eq([200, nil])
      end
    end

    context 'called with an invalid URL' do
      it 'should catch the error and raise n StackatoAppStoreAPIConnectionFailed error' do
        stub_request(:post, "http://127.0.0.1/").
          with(:body => "\"foo=1\"",
               :headers => {'Accept'=>'*/*', 
                            'Content-Type'=>'application/json', 
                            'User-Agent'=>'Ruby'}).
          to_raise(Errno::ECONNREFUSED)
        expect{ controller.http_post_json( "http://127.0.0.1", "foo=1" ) }.to raise_error( Errors::ApiError, /Could not connect to the AppStore API./)
      end

      it 'should catch the error and raise StackatoAppStoreAPITimeout error' do
        stub_request(:post, "http://127.0.0.1/").
          with(:body => "\"foo=1\"",
               :headers => {'Accept'=>'*/*', 
                            'Content-Type'=>'application/json', 
                            'User-Agent'=>'Ruby'}).
          to_timeout
        expect{ controller.http_post_json( "http://127.0.0.1", "foo=1" ) }.to raise_error( Errors::ApiError, /There was a timeout communicating with the AppStore API./)
      end
    end
  end
end
