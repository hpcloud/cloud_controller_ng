require "ostruct"
require "spec_helper"

describe VCAP::CloudController::Jobs::Runtime::Stackato::DockerRegistryCleanup do
  let(:config) {({docker_apps: {}})}
  let(:cleanup) {
    VCAP::CloudController::Jobs::Runtime::Stackato::DockerRegistryCleanup.new(config)
  }
  let(:apps) {[]}

  context '#perform' do
    before do
      allow(CloudController::DependencyLocator.instance).to receive(:docker_registry)
        .and_return("docker.registry:12345")
      allow(VCAP::CloudController::App).to receive(:where) do |&block|
        apps.select do |app|
          OpenStruct.new(app).instance_eval(&block)
        end.map do |app|
          droplets = app[:droplet_hash].map {|h| OpenStruct.new(droplet_hash: h)}
          OpenStruct.new(droplets: droplets)
        end.flatten
      end
      apps.clear
    end
    it 'should call out to the registry' do
      apps << { docker_image: nil, droplet_hash: ["not_a_docker_image"] }
      apps << { docker_image: "some_image", droplet_hash: ["1", "2"] }
      apps << { docker_image: "other_image", droplet_hash: ["0123456789abcdef"] }
      req = stub_request(:post, "http://docker.registry:12345/v1/cleanup/")
         .with(:body => "{\"cleanup_limit\":10240,\"known_hashes\":[\"1\",\"2\",\"0123456789abcdef\"]}")
      cleanup.perform
      expect(req).to have_been_made
    end
    it 'should support custom target sizes' do
      config[:docker_apps][:storage_limit_mb] = 12345
      req = stub_request(:post, "http://docker.registry:12345/v1/cleanup/")
         .with(:body => "{\"cleanup_limit\":12345,\"known_hashes\":[]}")
      cleanup.perform
      expect(req).to have_been_made
    end
  end
end
