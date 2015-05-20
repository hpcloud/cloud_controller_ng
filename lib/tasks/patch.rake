namespace :patch do
  desc 'collection of tasks that need to run during the patching process'
   
  task :update_appstore_url do
    require 'yaml'
   
    config_folder = '/home/stackato/stackato/code/cloud_controller_ng/config' 
    config_path = File.join(config_folder, 'cloud_controller.yml')
    if File.exists?(config_path)
      yml_config = YAML.load_file(config_path)
      yml_config.fetch('app_store', {}).fetch('stores', {}).each_pair do |name, data|
        new_url = data['content_url']
        existing = `/home/stackato/bin/kato config get cloud_controller_ng app_store/stores/#{name}/content_url`
        #Only update the URL if it is pointing to the get.stackato.com/store address.       
        if /.*get.stackato.com\/store\/.*/ =~ existing
          `/home/stackato/bin/kato config set cloud_controller_ng app_store/stores/#{name}/content_url #{new_url}`
        end
      end
    end 
  end
end

