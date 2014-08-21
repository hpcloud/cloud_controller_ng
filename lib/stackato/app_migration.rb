# Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.

require 'steno'

module VCAP::CloudController
  class AppMigration
    class << self

      def logger
        @logger ||= Steno.logger('cc.app_migration')
      end

      def migrate_app_to_space(app, space)

        migration_id = SecureRandom.hex(4)

        App.db.transaction do
          current_space = Space[:guid => app.space_guid]
          current_organization = Organization[:guid => current_space.organization_guid]

          new_space = space
          new_organization = Organization[:guid => new_space.organization_guid]

          logger.info("[#{migration_id}] Migrating application '#{app.name}' from #{current_organization.name}/#{current_space.name} to"\
                      " #{new_organization.name}/#{new_space.name}")

          routes = app.routes
          domains = routes.map { |route| route.domain }.reject { |domain| domain.shared? }
          service_instances = ServiceBinding.where(:app_id => app.id).map { |service_binding| ServiceInstance[:guid => service_binding.service_instance_guid] }
          is_moving_org = current_organization.guid != new_organization.guid

          validate_app_migration(app, domains, routes, service_instances, is_moving_org)

          if is_moving_org
            domains.each { |domain|
              logger.info("[#{migration_id}] Migrating domain '#{domain.name}' with application")
              domain.owning_organization = new_organization
              domain.save
            }
          end

          routes.each { |route|
            logger.info("[#{migration_id}] Migrating route '#{route.host}' with application")
            route.space = new_space
            route.save
          }

          service_instances.each { |service_instance|
            logger.info("[#{migration_id}] Migrating service instance '#{service_instance.name}' with application")
            service_instance.space = new_space
            service_instance.save
          }

          app.space = new_space
          app.save
        end

        logger.info("[#{migration_id}] Migration complete.")
      end

      private

      def app_names(migrating_app, conflicting_apps)
        conflicting_apps.reject { |app| app == migrating_app }.map { |app| "'#{app.name}'" }.join(',')
      end

      def validate_app_migration(app, domains, routes, service_instances, is_moving_org)

        if is_moving_org
          domains.each { |domain|
            apps = domain.routes.map { |route| route.apps }.flatten.uniq
            if apps.size != 1 || !apps.include?(app)
              raise Errors::ApiError.new_from_details(
                        'StackatoAppMigrationValidationFailed',
                        "Domains used by '#{app.name}' are also being used by #{app_names(app, apps)} and cannot be migrated.")
            end
          }
        end

        routes.each { |route|
          if route.apps.size != 1 || !route.apps.include?(app)
            raise Errors::ApiError.new_from_details(
                      'StackatoAppMigrationValidationFailed',
                      "Routes used by '#{app.name}' are also being used by #{app_names(app, apps)} and cannot be migrated.")
          end
        }

        service_instances.each { |service_instance|
          apps = service_instance.service_bindings.map { |service_binding| service_binding.app }
          if apps.size != 1 || !apps.include?(app)
            raise Errors::ApiError.new_from_details(
                      'StackatoAppMigrationValidationFailed',
                      "Service Instances used by '#{app.name}' are also being used by #{app_names(app, apps)} and cannot be migrated.")
          end
        }
      end
    end
  end
end