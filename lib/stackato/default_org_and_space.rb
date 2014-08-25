# Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.

require 'steno'

module VCAP::CloudController
  class DefaultOrgAndSpace
    class << self

      def logger
        @logger ||= Steno.logger('cc.default_org_and_space')
      end

      def add_user_to_individual_org(org, user, role)
        logger.debug("Adding user '#{user.guid}' to individual organization '#{org.name}' with role '#{role}'")
        org.add_user(user) # regardless of additional roles the user has to be a 'user' in the org
        case role
          when 'manager'
            org.add_manager(user)
          when 'billing_manager'
            org.add_billing_manager(user)
          when 'auditor'
            org.add_auditor(user)
        end
      end

      def add_user_to_individual_space(space, user, role)
        logger.debug("Adding user '#{user.guid}' to individual space '#{space.name}' with role '#{role}'")
        case role
          when 'manager'
            space.add_manager(user)
          when 'auditor'
            space.add_auditor(user)
          else
            space.add_developer(user)
        end
      end

      def create_individual_org_and_space_for_new_user(token, user)

        config = VCAP::CloudController::Config.config[:uaa][:new_user_strategies][:individual]
        space_name = config[:space_name] || 'default'
        quota_name = config[:quota_name] || 'default'
        space_role = config[:space_role] || 'developer'
        organization_role = config[:organization_role] || 'user'
        user_name = token['user_name']
        users_org = Organization[:name => user_name]

        # Create the org and enforce the quota only if it didn't already exist (allows admins to manually specialize setup)
        unless users_org
          quota_definition = QuotaDefinition.find(:name => quota_name)
          users_org = Organization.create(:name => user_name, :quota_definition => quota_definition)
        end

        # Add the user to their org
        add_user_to_individual_org(users_org, user, organization_role)
        users_org.save

        # Only create the users space if it didn't already exist
        users_space = Space[:name => space_name, :organization => users_org]
        unless users_space
          users_space = Space.create(:name => space_name, :organization => users_org)
        end

        # Add the user to their space
        add_user_to_individual_space(users_space, user, space_role)
        users_space.save
      end

      def add_user_to_global_default_org_and_space(user)
        default_org = Organization.where(:is_default => true).first
        if default_org
          logger.debug("Adding user '#{user.guid}' to global organization '#{default_org.name}' with role 'user'")
          default_org.add_user(user)
          default_space = Space.where(:is_default => true).first
          if default_space
            logger.debug("Adding user '#{user.guid}' to global space '#{default_space.name}' with role 'developer'")
            default_space.add_developer(user)
          end
        end
      end

      def add_user_to_default_org_and_space(token, user)
        begin
          # Default to the global strategy if the config is missing
          new_user_strategy = VCAP::CloudController::Config.config[:uaa][:new_user_strategy] || 'global'

          logger.debug("Processing new user '#{user.guid}' using strategy '#{new_user_strategy}'")

          if new_user_strategy == 'individual'
            create_individual_org_and_space_for_new_user(token, user)
          elsif new_user_strategy == 'global'
            add_user_to_global_default_org_and_space(user)
          else
            raise "Unrecognized new user strategy '#{new_user_strategy}'"
          end
        rescue => e
          logger.error("Unable to assign user '#{token['user_name']}' to default org and space using strategy '#{new_user_strategy}': #{e.message} : #{e.backtrace}")
        end
      end
    end
  end
end