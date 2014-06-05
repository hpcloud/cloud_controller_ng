
module VCAP; end

require 'stackato/spec_helper'
require 'cloud_controller/stackato/config'

describe VCAP::CloudController::StackatoConfig do

  before do
    reset_mocked_datastores
  end

  it 'should update info/support_address' do
    old_support_address = "jim@example.com"
    new_support_address = "bob@example.com"
    Kato::Config.set("cloud_controller_ng", "info/support_address", old_support_address)
    c = VCAP::CloudController::StackatoConfig.new("cloud_controller_ng")
    c.save({ "info" => { "support_address" => new_support_address } })
    Kato::Config.get("cloud_controller_ng", "info/support_address")
      .should eq new_support_address
  end

  it 'should not allow to write to invalid config' do
    # suppport_address should come under /info/ not top-level
    old_support_address = "jim@example.com"
    new_support_address = "bob@example.com"
    Kato::Config.set("cloud_controller_ng", "support_address", old_support_address)
    c = VCAP::CloudController::StackatoConfig.new("cloud_controller_ng")
    lambda { c.save({ "support_address" => new_support_address }) }
      .should raise_error VCAP::Errors::StackatoConfigUnsupportedUpdate
  end

  it 'should retrieve cc "staging" keys excluding "auth"' do
    c = VCAP::CloudController::StackatoConfig.new("cloud_controller_ng")
    Kato::Config.set("cloud_controller_ng", "staging", {
      "max_staging_runtime" => 480, # secs
      "auth" => {
        "user" => "placeholder",
        "password" => "placeholder"
      }
    })
    c.get_viewable.should eq({
      "staging" => {
        "max_staging_runtime" => 480
      }
    })
  end

  it 'should update cc keys if password excluded' do

    c = VCAP::CloudController::StackatoConfig.new("cloud_controller_ng")

    Kato::Config
      .should_receive(:set)
      .with(
        "cloud_controller_ng",
        "keys/token", "iamatoken",
        { :must_exist => true })
      .and_return(nil)

    Kato::Config
      .should_receive(:set)
      .with(
        "cloud_controller_ng",
        "keys/token_expiration", 604800,
        { :must_exist => true })
      .and_return(nil)

    c.save({
      "keys" => {
        "token" => 'iamatoken',
        "token_expiration" => 604800
      }
    })

  end

  it 'should update cc keys, excluding password, if password is included' do

    c = VCAP::CloudController::StackatoConfig.new("cloud_controller_ng")

    Kato::Config
      .should_receive(:set)
      .with(
        "cloud_controller_ng",
        "keys/token", "iamatoken",
        { :must_exist => true })
      .and_return(nil)

    Kato::Config
      .should_receive(:set)
      .with(
        "cloud_controller_ng",
        "keys/token_expiration", 604800,
        { :must_exist => true })
      .and_return(nil)

    # should NOT update password
    Kato::Config
      .should_not_receive(:set)
      .with(
        "cloud_controller_ng",
        "keys/password", "newpassword",
        { :must_exist => true })

    c.save({
      "keys" => {
        "token" => 'iamatoken',
        "token_expiration" => 604800,
        "password" => "newpassword"
      }
    })

  end

end

