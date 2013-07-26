require File.expand_path('../../../lib/cloud_controller/encryptor', __FILE__)

Sequel.migration do
  up do
    self[:apps].each do |row|
      salt = VCAP::CloudController::Encryptor.generate_salt
      encrypted = VCAP::CloudController::Encryptor.encrypt(row[:environment_json], salt)
      self["UPDATE apps SET encrypted_environment_json = ?, salt = ? WHERE id = ?", encrypted, salt, row[:id]].update
    end
    alter_table :apps do
      drop_column :environment_json
    end
  end

  down do
  end
end
