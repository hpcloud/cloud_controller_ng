# Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.

require 'steno'

module VCAP::CloudController
  class DefaultOrgAndSpace
    class << self

      def logger
        @logger ||= Steno.logger('cc.default_org_and_space')
      end

      def create_individual_org_and_space_for_new_user(token, user)

        config = VCAP::CloudController::Config.config[:uaa][:new_user_strategies][:individual]
        space_name = config[:space_name] || 'default'
        quota_name = config[:quota_name]|| 'default'
        user_name = token['user_name']
        users_org = Organization[:name => user_name]

        # Create the org and enforce the quota only if it didn't already exist (allows admins to manually specialize setup)
        unless users_org
          users_org = Organization.create(:name => user_name)
          users_org.quota_definition = QuotaDefinition.find(:name => quota_name)
        end

        # Add the user to the org with no roles
        users_org.add_user(user)
        users_org.save

        # Only create the users space if it didn't already exist
        users_space = Space[:name => space_name, :organization => users_org]
        unless users_space
          users_space = Space.create(:name => space_name, :organization => users_org)
        end

        # The user should only be a developer in the space
        users_space.add_developer(user)
        users_space.save
      end

      def add_user_to_global_default_org_and_space(user)
        default_org = Organization.where(:is_default => true).first
        if default_org
          default_org.add_user(user)
          default_space = Space.where(:is_default => true).first
          if default_space
            default_space.add_developer(user)
          end
        end
      end

      def ensure_user_belongs_to_default_org_and_space(token, user)

        # Use the logged_in_at property to determine if this is the user first time logging in
        unless user.logged_in_at
          begin

            # Default to the global strategy if the config is missing
            new_user_strategy = VCAP::CloudController::Config.config[:uaa][:new_user_strategy] || 'global'

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
end