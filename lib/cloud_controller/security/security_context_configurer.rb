require 'steno'

module VCAP::CloudController
  module Security
    class SecurityContextConfigurer
      def initialize(token_decoder)
        @token_decoder = token_decoder
        @logger ||= Steno.logger("cc.security_context")
      end

      def configure(header_token)
        VCAP::CloudController::SecurityContext.clear
        token_information = decode_token(header_token)

        user = user_from_token(token_information)

        VCAP::CloudController::SecurityContext.set(user, token_information)
      rescue VCAP::UaaTokenDecoder::BadToken
        VCAP::CloudController::SecurityContext.set(nil, :invalid_token)
      end

      private

      def decode_token(header_token)
        token_information = @token_decoder.decode_token(header_token)
        return nil if token_information.nil? || token_information.empty?

        if !token_information['user_id'] && token_information['client_id']
          token_information['user_id'] = token_information['client_id']
        end
        token_information
      end

      def create_default_org_and_space_for_new_user(token, user)

        config = VCAP::CloudController::Config.config[:uaa][:new_user_strategies][:autoassign]
        space_name = config[:space_name]
        quota_name = config[:quota_name]

        users_org = Organization.create(:name => token['email'] || token['user_name'])
        users_org.quota_definition = QuotaDefinition.find(:name => quota_name || 'default')
        users_org.add_user(user)
        users_org.save
        users_space = Space.create(:name => space_name || 'default', :organization => users_org)
        users_space.add_developer(user)
        users_space.save
      end

      def add_user_to_system_default_org_and_space(user)
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
            new_user_strategy = VCAP::CloudController::Config.config[:uaa][:new_user_strategy]

            if new_user_strategy == 'autoassign'
              create_default_org_and_space_for_new_user(token, user)
            else
              add_user_to_system_default_org_and_space(user)
            end
          rescue => e
            @logger.error("Unable to assign user '#{token['user_name']}' to default org and space using strategy '#{new_user_strategy}': #{e.message}")
          end
        end
      end

      def update_user_logged_in_time(token, user)

        login_timestamp = Time.at(token['iat']) rescue nil

        if login_timestamp && user.logged_in_at != login_timestamp
          user.logged_in_at = login_timestamp
          user.save
        end
      end

      def update_user_admin_status(token, user)
        admin = VCAP::CloudController::Roles.new(token).admin?
        user.update_from_hash(admin: admin) if user.admin != admin
      end

      def user_from_token(token)
        user_guid = token && token['user_id']
        return unless user_guid

        user = User.find(guid: user_guid.to_s)

        if user
          ensure_user_belongs_to_default_org_and_space(token, user)
        else
          User.db.transaction do
            user = User.create(guid: user_guid, active: true)
            ensure_user_belongs_to_default_org_and_space(token, user)
          end
        end

        update_user_logged_in_time(token, user)
        update_user_admin_status(token, user)

        return user
      end
    end
  end
end
