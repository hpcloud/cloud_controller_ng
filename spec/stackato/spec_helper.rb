
require "rspec"
require 'kato/config'
require 'kato/config/datastore/memory'
require 'kato/node_process_controller'
require 'kato/node_process_controller/client/mock'
require 'kato/logging'
require 'kato/cluster/process'
require 'kato/cluster/role'
require 'kato/local/redis/config'
require 'kato/local/config'

RSpec.configure do |config|
  ::Kato::Config.datastore = ::Kato::ConfigDatastore::Memory.instance
  ::Kato::NodeProcessController.client_class =
    ::Kato::NodeProcessControllerClient::Mock
  ::Kato::Cluster::Process::Manager.load_process_spec(
    File.expand_path("../fixtures/basic/etc/kato/processes", __FILE__))
  ::Kato::Cluster::Process::Manager.load_process_order(
    File.expand_path("../fixtures/basic/etc/kato/process_order.yml", __FILE__))
  ::Kato::Cluster::Process::Manager.load_process_alternatives(
    File.expand_path("../fixtures/basic/etc/kato/process_alternatives.yml", __FILE__))
  ::Kato::Cluster::RoleManager.load_roles_config(
    File.expand_path("../fixtures/basic/etc/kato/role_order.yml", __FILE__))
  ::Kato::Cluster::RoleManager.load_role_groups(
    File.expand_path("../fixtures/basic/etc/kato/role_groups.yml", __FILE__))
  ::Kato::Logging.level = ::Logger::FATAL
end

def reset_mocked_datastores
  Kato::Config.datastore.reset
  ["127.0.0.1", "1.2.3.4", "5.6.7.8"].each do |node_ip|
    Kato::NodeProcessController.new(node_ip).client.reset
  end
end

def mock_redis_uri_storage(uri="redis://127.0.0.1:7474/0")
  # Mock redis_uri storage
  @redis_uri = uri
  Kato::Local::Redis::Config
    .stub(:_read_uri)
    .and_return(@redis_uri)
  Kato::Local::Redis::Config
    .stub(:_persist_uri) do |filename, content|
      @redis_uri = content
    end
end

def mock_node_type_storage(node_type=Kato::Local::Node::NODE_TYPE_MICRO)
  # mock node_type storage
  @local_node_type = node_type
  Kato::Local::Node
    .stub(:get_node_type)
    .and_return(@local_node_type)
  Kato::Local::Node
    .stub(:set_node_type) do |node_type|
      @local_node_type = node_type
    end
end

def mock_determine_external_ip(external_ip)
  @new_node_external_ip = external_ip
  # mock determining our external ip
  Kato::Local::Util
    .stub(:get_ip_address)
    .and_return(@new_node_external_ip)
end

def mock_hostname(hostname="stackato-test.local")
  @hostname = hostname
  # mock determining our external ip
  Kato::Local::Config
    .stub(:get_current_hostname)
    .and_return(@hostname)
end

