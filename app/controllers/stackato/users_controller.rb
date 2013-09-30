require "uaa/token_issuer"
require "uaa/scim"
module VCAP::CloudController
  rest_controller :StackatoUsers do
    ADMIN_GROUP = "cloud_controller.admin"
    path_base('stackato/users')

    # There's a model() method to do this but it breaks things
    def model; User; end

    # Attributes defined here control what gets extracted from
    # the POST body during CreateMessage instantiation.
    define_attributes do
      attribute :username, String
      attribute :given_name, String, :default => nil
      attribute :family_name, String
      attribute :email, Message::EMAIL
      attribute :phone, String
      attribute :password, String, :exclude_in => [:read, :enumerate]
      attribute :admin, Message::Boolean, :default => false
    end

    # def self.translate_validation_exception(e, attributes)
    #   guid_errors = e.errors.on(:guid)
    #   if guid_errors && guid_errors.include?(:unique)
    #     Errors::UaaIdTaken.new(attributes["guid"])
    #   else
    #     Errors::UserInvalid.new(e.errors.full_messages)
    #   end
    # end

    def create
      raise Errors::NotAuthenticated unless user
      raise Errors::NotAuthorized unless roles.admin?


      json = body.read
      logger.debug "JSON POST body: #{json.inspect}"
      json_msg = self.class::CreateMessage.decode(json)
      @request_attrs = json_msg.extract(:stringify_keys => true)
      logger.debug "Request Atts: #{request_attrs.inspect}"
      user_info = {
        :userName => request_attrs["username"],
        :name => {
          :givenName => request_attrs["given_name"],
          :familyName => request_attrs["family_name"]
        },
        :emails => [
          :value => request_attrs["email"] #TODO: support multiple emails
        ],
        :phoneNumbers => [
          :value => request_attrs["phone"] #TODO: support multiple phones
        ],
        :password => request_attrs["password"]
      }

      logger.debug "User info to post to UAA: #{user_info.inspect}"

      target = Kato::Config.get("cloud_controller_ng", 'uaa/url')

      #TODO: generate this, retrieve it from config
      secret = 'cloudcontrollersecret'

      token_issuer =
        CF::UAA::TokenIssuer.new(target, 'cloud_controller', secret)


      token = token_issuer.client_credentials_grant

      scim_client = CF::UAA::Scim.new(target, token.auth_header)


      before_create
      obj = nil
      model.db.transaction do
        scim_user = scim_client.add :user, user_info
        logger.debug "Response from SCIM user creation: #{scim_user.inspect}"

        if request_attrs["admin"]
          scim_group = scim_client.query( :group, 'filter' => %Q!displayName eq "#{ADMIN_GROUP}"!, 'startIndex' => 1)["resources"].first
          group_guid = scim_group["id"]
          members = scim_group["members"].collect{|hash|hash["value"]}
          members << scim_user['id']
          group_info = {
            "id" => group_guid,
            "schemas" => scim_group['schemas'],
            "members" => members,
            "meta" => scim_group['meta'],
            "displayName" => ADMIN_GROUP
          }
          logger.debug "updated group info to put: #{group_info.inspect}"
          scim_client.put :group, group_info
        end

        cc_user_info = {
          'guid' => scim_user['id'],
          'admin' => request_attrs["admin"] # Should I extract this from scim_user?
        }
        obj = model.create_from_hash(cc_user_info)
        validate_access(:create, obj, user, roles)
      end

      after_create(obj)

      [ HTTP::CREATED,
        { "Location" => "#{UsersController.path}/#{obj.guid}" },
        serialization.render_json(UsersController, obj, @opts)
      ]
    rescue CF::UAA::InvalidToken => e
      logger.error "The token for the 'cloud_controller' oauth2 client was
      not accepted by #{target}. This should never happen."
      raise e
    rescue CF::UAA::TargetError => e
      # Probably a validation error coming from the target.
      return 400, e.info.to_json
    rescue Exception => e
      #TODO: Rollback UAA user creation.
      raise e
    end

    def enumerate
      raise Errors::NotAuthenticated unless user
      # TODO: stub, here to satisfy tests
      return {}.to_json
    end

    def read
      # TODO: implement or not
      raise "Not Implemented"
    end

    def update
      # TODO: implement or not
      raise "Not Implemented"
    end

    def delete
      # TODO: implement or not
      raise "Not Implemented"
    end

  end
end
