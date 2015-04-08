module VCAP::CloudController
  module StackatoScimUtils
    def scim_api
      target = Kato::Config.get("cloud_controller_ng", 'uaa/url')
      secret = Kato::Config.get("cloud_controller_ng", 'aok/client_secret')
      skip_cert_verify = Kato::Config.get("cloud_controller_ng",
                                          'skip_cert_verify')
      # By default ignore certs.
      skip_cert_verify = true if skip_cert_verify.nil? 
      token_issuer =
        CF::UAA::TokenIssuer.new(target, 'cloud_controller', secret,
                                 :skip_ssl_validation => skip_cert_verify)
      token = token_issuer.client_credentials_grant
      return CF::UAA::Scim.new(target, token.auth_header,
                               :skip_ssl_validation => skip_cert_verify)
    end
    module_function :scim_api
  end
end
