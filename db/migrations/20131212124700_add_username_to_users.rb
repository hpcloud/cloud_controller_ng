$:.unshift(File.expand_path("../../../lib", __FILE__))
$:.unshift(File.expand_path("../../../app", __FILE__))

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __FILE__)

require "pg"
require "kato/config"
require "kato/util"

def connect_aok_pg
  db_config = Kato::Util.symbolize_keys(Kato::Config.get("aok", "database_environment/production"))
  ::PG.connect( :host => db_config[:host], :port => db_config[:port], :dbname => db_config[:database], :user => db_config[:username], :password => db_config[:password] )
end

def pull_user_from_aok(aok_connection, guid)
  aok_connection.exec("select * from identities where guid=$1", [guid]) do |result|
    result.each do |row|
      db_guid = parse_pg( row.values_at('guid') )
      next unless guid == db_guid
      name = parse_pg( row.values_at('username') )
      return name
    end
  end

  return nil
end

Sequel.migration do
  change do
    alter_table(:users) do
      add_column :username, String, :default => nil, :case_insenstive => true
      add_index :username
    end

    aok_conn = nil

    from(:users).where(:username => nil).each do |user|
      aok_conn ||= connect_aok_pg
      begin
        guid = user[:guid]
        username = pull_user_from_aok(aok_conn, guid)
        if username
          from(:users).where(:guid => guid).update(:username => username)
          puts "Cached username for user with guid #{guid}: #{username}" 
        else
          puts "User with guid #{user[:guid]} doesn't exist in AOK. Skipping."
        end
      end
    end
  end
end