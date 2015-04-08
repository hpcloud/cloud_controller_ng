# Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.

require 'spec_helper'

describe 'Application Migration', non_transactional: true do

  it 'migrates apps between spaces in the same organization' do

    VCAP::CloudController::SecurityContext.set(nil, {'scope' => ['cloud_controller.admin']})
    org = VCAP::CloudController::Organization.create(:name => 'test_org')
    space1 = VCAP::CloudController::Space.create(:name => 'test_space_1', :organization => org)
    space2 = VCAP::CloudController::Space.create(:name => 'test_space_2', :organization => org)

    app = VCAP::CloudController::App.create(:name => 'test-app', :space => space1)

    expect(app.space.guid).to eq(space1.guid)
    VCAP::CloudController::AppMigration.migrate_app_to_space(app, space2)

    app = VCAP::CloudController::App[:guid => app.guid]
    expect(app.space.guid).to eq(space2.guid)
  end

  it 'migrates apps between spaces in different organizations' do

    VCAP::CloudController::SecurityContext.set(nil, {'scope' => ['cloud_controller.admin']})
    org1 = VCAP::CloudController::Organization.create(:name => 'test_org_1')
    org2 = VCAP::CloudController::Organization.create(:name => 'test_org_2')
    space1 = VCAP::CloudController::Space.create(:name => 'test_space_1', :organization => org1)
    space2 = VCAP::CloudController::Space.create(:name => 'test_space_2', :organization => org2)

    app = VCAP::CloudController::App.create(:name => 'test-app', :space => space1)

    expect(app.space.guid).to eq(space1.guid)
    VCAP::CloudController::AppMigration.migrate_app_to_space(app, space2)

    app = VCAP::CloudController::App[:guid => app.guid]
    expect(app.space.guid).to eq(space2.guid)
  end

  it 'migrates apps with many routes' do

    VCAP::CloudController::SecurityContext.set(nil, {'scope' => ['cloud_controller.admin']})
    org = VCAP::CloudController::Organization.create(:name => 'test_org')
    space1 = VCAP::CloudController::Space.create(:name => 'test_space_1', :organization => org)
    space2 = VCAP::CloudController::Space.create(:name => 'test_space_2', :organization => org)
    domain1 = VCAP::CloudController::SharedDomain.find_or_create('test.com')
    domain2 = VCAP::CloudController::SharedDomain.find_or_create('bar.com')
    route1 = VCAP::CloudController::Route.create(:domain => domain1, :space => space1, :host => 'foo1')
    route2 = VCAP::CloudController::Route.create(:domain => domain2, :space => space1, :host => 'foo2')
    app = VCAP::CloudController::App.create(:name => 'test-app', :space => space1)
    route1.add_app(app)
    route2.add_app(app)

    expect(app.space.guid).to eq(space1.guid)
    VCAP::CloudController::AppMigration.migrate_app_to_space(app, space2)

    # Re-read models to get updated properties
    app = VCAP::CloudController::App[:guid => app.guid]
    route1 = VCAP::CloudController::Route[:guid => route1.guid]
    route2 = VCAP::CloudController::Route[:guid => route2.guid]

    # Routes should have been migrated with the application
    expect(app.space.guid).to eq(space2.guid)
    expect(route1.space.guid).to eq(space2.guid)
    expect(route2.space.guid).to eq(space2.guid)
  end

  context 'migrating apps with domains across orgs' do
    let(:org1) { VCAP::CloudController::Organization.create(:name => 'test_org_1') }
    let(:org2) { VCAP::CloudController::Organization.create(:name => 'test_org_2') }
    let(:space1) { VCAP::CloudController::Space.create(:name => 'test_space_1', :organization => org1) }
    let(:space2) { VCAP::CloudController::Space.create(:name => 'test_space_2', :organization => org2) }
    before do
      VCAP::CloudController::SecurityContext.set(nil, {'scope' => ['cloud_controller.admin']})
    end
    it 'fails to migrate private domains with apps between spaces in different organizations' do
      domain1 = VCAP::CloudController::PrivateDomain.create(:name => "foobar.com", :owning_organization => org1)
      route1 = VCAP::CloudController::Route.create(:domain => domain1, :space => space1, :host => 'foo')
      app = VCAP::CloudController::App.create(:name => 'test-app', :space => space1)
      route1.add_app(app)
  
      expect(app.space.guid).to eq(space1.guid)
      expect {
        VCAP::CloudController::AppMigration.migrate_app_to_space(app, space2)
      }.to raise_error(VCAP::Errors::ApiError, "The domain is invalid: the owning organization cannot be changed")
    end
  
    it 'migrates apps with shared domains across spaces in different organizations' do
      domain1 = VCAP::CloudController::SharedDomain.create(:name => "foobar.com")
      route1 = VCAP::CloudController::Route.create(:domain => domain1, :space => space1, :host => 'foo')
      app = VCAP::CloudController::App.create(:name => 'test-app', :space => space1)
      route1.add_app(app)
  
      expect(app.space.guid).to eq(space1.guid)
      VCAP::CloudController::AppMigration.migrate_app_to_space(app, space2)
  
      # Re-read models to get updated properties
      app = VCAP::CloudController::App[:guid => app.guid]
      domain1 = VCAP::CloudController::SharedDomain[:guid => domain1.guid]
      route1 = VCAP::CloudController::Route[:guid => route1.guid]
  
      expect(app.space.guid).to eq(space2.guid)
      expect(domain1.owning_organization).to be(nil)
      expect(route1.space.guid).to eq(space2.guid)
    end
  end

  # TODO test service migration, migration should fail if routes, domains or services are in use by more than one app
end
