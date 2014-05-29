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

      def user_from_token(token)
        user_guid = token && token['user_id']
        return unless user_guid
        admin = VCAP::CloudController::Roles.new(token).admin?
        user = User.find(guid: user_guid.to_s)
        login_timestamp = Time.at(token['iat']) rescue nil
        if user
          if login_timestamp && user.logged_in_at != login_timestamp
            user.logged_in_at = login_timestamp
            user.save
          end
          return user 
        end
        
        User.db.transaction do
          user = User.create(guid: user_guid, admin: admin, active: true, logged_in_at: login_timestamp)
          default_org = Organization.where(:is_default => true).first
          if default_org
            default_org.add_user(user)
            default_space = Space.where(:is_default => true).first
            if default_space
              default_space.add_developer(user)
            end
          end
        end

        return user
      end
    end
  end
end
