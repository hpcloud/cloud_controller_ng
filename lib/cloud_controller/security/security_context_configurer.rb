require 'stackato/default_org_and_space'

module VCAP::CloudController
  module Security
    class SecurityContextConfigurer
      def initialize(token_decoder)
        @token_decoder = token_decoder
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

        unless user
          User.db.transaction do
            user = User.create(guid: user_guid, active: true)
            VCAP::CloudController::DefaultOrgAndSpace.add_user_to_default_org_and_space(token, user)
          end
        end

        update_user_logged_in_time(token, user)
        update_user_admin_status(token, user)

        return user
      end
    end
  end
end
