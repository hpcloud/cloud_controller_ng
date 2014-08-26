# Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.

require 'spec_helper'

describe 'Cloud Controller', type: :integration, non_transactional: false do
  before(:all) do
    $spec_env.reset_database_with_seeds
    start_nats
  end

  after(:all) do
    stop_nats
  end

  it 'adds new user to global org and space' do

    # Configure global orgs and spaces
    config_override({:uaa => config[:uaa].merge(:new_user_strategy => 'global')})

    # Ensure global orgs and spaces are configured
    VCAP::CloudController::SecurityContext.set(nil, {'scope' => ['cloud_controller.admin']})
    org = VCAP::CloudController::Organization.create(:name => "test_org_#{Time.now.to_i}", :is_default => true).save
    space = VCAP::CloudController::Space.create(:name => "test_space_#{Time.now.to_i}", :organization => org, :is_default => true).save

    # Access the cc api as a 'new' user for the first time
    user_guid = Sham.guid
    user_name = 'test_user'
    user_token = user_token(user_guid, user_name, false)
    user = VCAP::CloudController::User.create(guid: user_guid, active: true)

    VCAP::CloudController::DefaultOrgAndSpace.add_user_to_default_org_and_space(user_token, user)

    # User should now exist and be in the default org and space
    expect(user).not_to eq(nil)
    expect(user.guid).to eq(user_guid)
    expect(user.organizations.map { |o| o.guid }).to include(org.guid)
    expect(user.spaces.map { |s| s.guid }).to include(space.guid)

    # User should not have any roles in the org, they should just be a basic user
    expect(org.managers.map { |o| o.guid }).not_to include(user.guid)
    expect(org.billing_managers.map { |o| o.guid }).not_to include(user.guid)
    expect(org.auditors.map { |o| o.guid }).not_to include(user.guid)
    expect(org.users.map { |o| o.guid }).to include(user.guid)

    # User should just be a developer in the space, nothing else
    expect(space.managers.map { |s| s.guid }).not_to include(user.guid)
    expect(space.auditors.map { |s| s.guid }).not_to include(user.guid)
    expect(space.developers.map { |s| s.guid }).to include(user.guid)
  end

  it 'adds new user to individual org and space' do

    # Configure individual orgs and spaces
    strategy_config = {
        :space_name => 'default',
        :quota_name => 'default',
        :space_role => 'developer',
        :organization_role => 'user'
    }
    config_override({:uaa => config[:uaa].merge(:new_user_strategy => 'individual', :new_user_strategies => {:individual => strategy_config})})

    # Access the cc api as a 'new' user for the first time
    user_guid = Sham.guid
    user_name = 'test_user'
    user_token = user_token(user_guid, user_name, false)
    user = VCAP::CloudController::User.create(guid: user_guid, active: true)

    VCAP::CloudController::DefaultOrgAndSpace.add_user_to_default_org_and_space(user_token, user)

    # User should now exist
    config = VCAP::CloudController::Config.config[:uaa][:new_user_strategies][:individual]
    expect(user).not_to eq(nil)
    expect(user.guid).to eq(user_guid)

    # Individual org and space for the user should exist
    org = VCAP::CloudController::Organization[:name => user_name]
    expect(org).not_to eq(nil)
    space = VCAP::CloudController::Space[:name => config[:space_name], :organization => org]
    expect(space).not_to eq(nil)

    # User should belong to their org and space
    expect(user).not_to eq(nil)
    expect(user.guid).to eq(user_guid)
    expect(user.organizations.map { |o| o.guid }).to include(org.guid)
    expect(user.spaces.map { |s| s.guid }).to include(space.guid)

    # User should not have any roles in the org, they should just be a basic user
    expect(org.managers.map { |o| o.guid }).not_to include(user.guid)
    expect(org.billing_managers.map { |o| o.guid }).not_to include(user.guid)
    expect(org.auditors.map { |o| o.guid }).not_to include(user.guid)
    expect(org.users.map { |o| o.guid }).to include(user.guid)

    # User should just be a developer in the space, nothing else
    expect(space.managers.map { |s| s.guid }).not_to include(user.guid)
    expect(space.auditors.map { |s| s.guid }).not_to include(user.guid)
    expect(space.developers.map { |s| s.guid }).to include(user.guid)
  end

  it 'adds new user to individual org and space when org and space already exist' do

    # Configure individual orgs and spaces
    strategy_config = {
        :space_name => 'default',
        :quota_name => 'default',
        :space_role => 'developer',
        :organization_role => 'user'
    }
    config_override({:uaa => config[:uaa].merge(:new_user_strategy => 'individual', :new_user_strategies => {:individual => strategy_config})})

    # Create the users individual org and space
    user_guid = Sham.guid
    user_name = 'test_user'
    config = VCAP::CloudController::Config.config[:uaa][:new_user_strategies][:individual]
    org = VCAP::CloudController::Organization.create(:name => user_name).save
    space = VCAP::CloudController::Space.create(:name => config[:space_name], :organization => org).save

    # Access the cc api as a 'new' user for the first time
    user_token = user_token(user_guid, user_name, false)
    user = VCAP::CloudController::User.create(guid: user_guid, active: true)

    VCAP::CloudController::DefaultOrgAndSpace.add_user_to_default_org_and_space(user_token, user)

    # User should now exist
    expect(user).not_to eq(nil)
    expect(user.guid).to eq(user_guid)

    # User should belong to their org and space
    expect(user).not_to eq(nil)
    expect(user.guid).to eq(user_guid)
    expect(user.organizations.map { |o| o.guid }).to include(org.guid)
    expect(user.spaces.map { |s| s.guid }).to include(space.guid)

    # User should not have any roles in the org, they should just be a basic user
    expect(org.managers.map { |o| o.guid }).not_to include(user.guid)
    expect(org.billing_managers.map { |o| o.guid }).not_to include(user.guid)
    expect(org.auditors.map { |o| o.guid }).not_to include(user.guid)
    expect(org.users.map { |o| o.guid }).to include(user.guid)

    # User should just be a developer in the space, nothing else
    expect(space.managers.map { |s| s.guid }).not_to include(user.guid)
    expect(space.auditors.map { |s| s.guid }).not_to include(user.guid)
    expect(space.developers.map { |s| s.guid }).to include(user.guid)
  end

  it 'adds new user to individual org and space with configurable roles' do

    # Configure individual orgs and spaces with custom roles
    strategy_config = {
        :space_name => 'default',
        :quota_name => 'default',
        :space_role => 'manager',
        :organization_role => 'manager'
    }
    config_override({:uaa => config[:uaa].merge(:new_user_strategy => 'individual', :new_user_strategies => {:individual => strategy_config})})

    # Access the cc api as a 'new' user for the first time
    user_guid = Sham.guid
    user_name = 'test_user'
    user_token = user_token(user_guid, user_name, false)
    user = VCAP::CloudController::User.create(guid: user_guid, active: true)

    VCAP::CloudController::DefaultOrgAndSpace.add_user_to_default_org_and_space(user_token, user)

    # User should now exist
    config = VCAP::CloudController::Config.config[:uaa][:new_user_strategies][:individual]
    expect(user).not_to eq(nil)
    expect(user.guid).to eq(user_guid)

    # Individual org and space for the user should exist
    org = VCAP::CloudController::Organization[:name => user_name]
    expect(org).not_to eq(nil)
    space = VCAP::CloudController::Space[:name => config[:space_name], :organization => org]
    expect(space).not_to eq(nil)

    # User should belong to their org and space
    expect(user).not_to eq(nil)
    expect(user.guid).to eq(user_guid)
    expect(user.organizations.map { |o| o.guid }).to include(org.guid)
    expect(user.managed_spaces.map { |s| s.guid }).to include(space.guid)

    # User should be a manager of the org
    expect(org.managers.map { |o| o.guid }).to include(user.guid)
    expect(org.billing_managers.map { |o| o.guid }).not_to include(user.guid)
    expect(org.auditors.map { |o| o.guid }).not_to include(user.guid)
    expect(org.users.map { |o| o.guid }).to include(user.guid)

    # User should be a manager of the space
    expect(space.managers.map { |s| s.guid }).to include(user.guid)
    expect(space.auditors.map { |s| s.guid }).not_to include(user.guid)
    expect(space.developers.map { |s| s.guid }).not_to include(user.guid)
  end

  it 'adds new user to individual org and space with configurable quota' do

    # Configure individual orgs and spaces with custom quota
    strategy_config = {
        :space_name => 'default',
        :quota_name => 'custom',
        :space_role => 'developer',
        :organization_role => 'user'
    }
    config_override({:uaa => config[:uaa].merge(:new_user_strategy => 'individual', :new_user_strategies => {:individual => strategy_config})})

    # Ensure the custom quota exists
    VCAP::CloudController::SecurityContext.set(nil, {'scope' => ['cloud_controller.admin']})
    quota = VCAP::CloudController::QuotaDefinition.create(:name =>'custom',:memory_limit => 2048, :total_services => 100,
                                                          :non_basic_services_allowed => true, :total_routes => 1000, :trial_db_allowed => true, :allow_sudo => false)

    # Access the cc api as a 'new' user for the first time
    user_guid = Sham.guid
    user_name = 'test_user'
    user_token = user_token(user_guid, user_name, false)
    user = VCAP::CloudController::User.create(guid: user_guid, active: true)

    VCAP::CloudController::DefaultOrgAndSpace.add_user_to_default_org_and_space(user_token, user)

    # User should now exist
    config = VCAP::CloudController::Config.config[:uaa][:new_user_strategies][:individual]
    expect(user).not_to eq(nil)
    expect(user.guid).to eq(user_guid)

    # Individual org and space for the user should exist
    org = VCAP::CloudController::Organization[:name => user_name]
    expect(org).not_to eq(nil)
    space = VCAP::CloudController::Space[:name => config[:space_name], :organization => org]
    expect(space).not_to eq(nil)

    # Org should have custom quota
    expect(org.quota_definition.guid).to eq(quota.guid)

    # User should belong to their org and space
    expect(user).not_to eq(nil)
    expect(user.guid).to eq(user_guid)
    expect(user.organizations.map { |o| o.guid }).to include(org.guid)
    expect(user.spaces.map { |s| s.guid }).to include(space.guid)

    # User should not have any roles in the org, they should just be a basic user
    expect(org.managers.map { |o| o.guid }).not_to include(user.guid)
    expect(org.billing_managers.map { |o| o.guid }).not_to include(user.guid)
    expect(org.auditors.map { |o| o.guid }).not_to include(user.guid)
    expect(org.users.map { |o| o.guid }).to include(user.guid)

    # User should just be a developer in the space, nothing else
    expect(space.managers.map { |s| s.guid }).not_to include(user.guid)
    expect(space.auditors.map { |s| s.guid }).not_to include(user.guid)
    expect(space.developers.map { |s| s.guid }).to include(user.guid)
  end
end