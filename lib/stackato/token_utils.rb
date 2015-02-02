# Copyright (c) ActiveState 2015 - ALL RIGHTS RESERVED.

require 'steno'
require 'uaa/info'

module VCAP::CloudController
  class TokenUtils
    class << self

      def logger
        @logger ||= Steno.logger('cc.stackato.token_utils')
      end

      # Validates the provided oauth token against the given auth server end point
      def validate_token(oauth_token, token_type, url, username, password)
        if oauth_token.nil?
          return
        end

        # Validate the decoded oauth token against the check_token endpoint
        begin
          info = CF::UAA::Info.new(url)
          token_data = oauth_token.sub(/^bearer /i, '')
          result = info.decode_token(username, password, token_data, token_type)

          # Check if the access token has been set inactive and throw as necessary.
          if result['access_token']['active'] == false
            raise CF::UAA::TokenExpired.new('Access Token is no longer active')
          end
        rescue Exception => e
          if e.class == CF::UAA::TokenExpired
            raise e
          else
            logger.warn "Unable to validate auth token against AOK\n#{e.message}"
          end
        end
      end

    end
  end
end