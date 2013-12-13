$:.unshift(File.expand_path("../../../lib", __FILE__))
$:.unshift(File.expand_path("../../../app", __FILE__))

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __FILE__)

require "uaa/token_issuer"
require "uaa/scim"
require "kato/config"

def scim_client
  return @scim_client if @scim_client
  external_domain = Kato::Config.get("cloud_controller_ng", 'external_domain')
  target = "https://#{external_domain}/uaa"
  secret = Kato::Config.get("cloud_controller_ng", 'aok/client_secret')
  token_issuer = CF::UAA::TokenIssuer.new(target, 'cloud_controller', secret)
  token = token_issuer.client_credentials_grant
  @scim_client = CF::UAA::Scim.new(target, token.auth_header)
  return @scim_client
end

Sequel.migration do
  change do
    alter_table(:users) do
      add_column :username, String, :default => nil, :case_insenstive => true
      add_index :username
    end

    from(:users).where(:username => nil).each do |user|
      begin
        guid = user[:guid]
        result = scim_client.get(:user, guid)
        username = result["username"]
        from(:users).where(:guid => guid).update(:username => username)
        puts "Cached username for user with guid #{guid}: #{username}" 
      rescue CF::UAA::NotFound
        puts "User with guid #{user[:guid]} doesn't exist in AOK. Skipping."
      end
    end
  end
end