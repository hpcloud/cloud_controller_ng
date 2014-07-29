# Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.

require 'spec_helper'

describe 'Cloud Controller', type: :integration, non_transactional: true do
  before(:all) do
    start_nats
  end

  after(:all) do
    stop_cc
    stop_nats
  end

  # TODO
  # Should only be 'user' in org and 'developer' in space (global and individual)
  # Individual should still work if org and/or space exist already

  it 'adds new user to global org and space' do

    # Configure global orgs and spaces
    run_cmd('/home/stackato/bin/kato config set cloud_controller_ng uaa/new_user_strategy global')
    stop_cc
    start_cc

    # Ensure global orgs and spaces are configured
    VCAP::CloudController::SecurityContext.set(nil, {'scope' => ['cloud_controller.admin']})
    org = VCAP::CloudController::Organization.create(:name => "test_org_#{Time.now.to_i}", :is_default => true).save
    space = VCAP::CloudController::Space.create(:name => "test_space_#{Time.now.to_i}", :organization => org, :is_default => true).save

    # Access the cc api as a 'new' user for the first time
    user_id = Sham.guid
    user_name = 'test_user'
    authorized_token = {'Authorization' => "bearer #{user_token(user_id, user_name)}"}
    make_get_request('/v2/info', authorized_token).tap do |r|
      r.code.should == '200'
    end
    user = VCAP::CloudController::User[:guid => user_id]

    # User should now exist and be in the default org and space
    expect(user).not_to eq(nil)
    expect(user.guid).to eq(user_id)
    expect(user.organizations.map { |o| o.guid }).to include(org.guid)
    expect(user.spaces.map { |s| s.guid }).to include(space.guid)
  end

  it 'adds new user to individual org and space' do

    # Configure individual orgs and spaces
    run_cmd('/home/stackato/bin/kato config set cloud_controller_ng uaa/new_user_strategy individual')
    stop_cc
    start_cc

    # Access the cc api as a 'new' user for the first time
    user_id = Sham.guid
    user_name = 'test_user'
    authorized_token = {'Authorization' => "bearer #{user_token(user_id, user_name)}"}
    make_get_request('/v2/info', authorized_token).tap do |r|
      r.code.should == '200'
    end
    user = VCAP::CloudController::User[:guid => user_id]

    # User should now exist and be in their individual org and space
    config = VCAP::CloudController::Config.config[:uaa][:new_user_strategies][:individual]
    expect(user).not_to eq(nil)
    expect(user.guid).to eq(user_id)
    expect(user.organizations.map { |o| o.name }).to include(user_name)
    expect(user.spaces.map { |s| s.name }).to include(config[:space_name])
  end
end
