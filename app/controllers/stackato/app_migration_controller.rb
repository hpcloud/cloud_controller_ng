# Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.

require 'stackato/app_migration'

module VCAP::CloudController
  class AppMigrationController < RestController::ModelController
    define_attributes do
      to_one :app
    end

    path_base 'stackato/apps'
    define_messages
    define_routes

    def migrate_app(app_guid)

      raise Errors::ApiError.new_from_details("NotAuthorized") unless SecurityContext.admin?

      app = App[:guid => app_guid]
      body_params = Yajl::Parser.parse(body)
      space_guid = body_params['space_guid']

      raise Errors: ApiError.new_from_details("NotFound") unless app
      raise Errors: ApiError.new_from_details("InvalidRequest") unless space_guid

      space = Space[:guid => space_guid]

      raise Errors: ApiError.new_from_details("NotFound") unless space

      AppMigration.migrate_app_to_space(app, space)

      [HTTP::OK, nil]
    end

    post "#{path_guid}/migrate", :migrate_app
  end
end
