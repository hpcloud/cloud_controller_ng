require "uaa/token_issuer"
require "uaa/scim"
require_relative 'stackato_user_creation'
module VCAP::CloudController
  rest_controller :StackatoUsers do
    include StackatoUserCreation
    path_base('stackato/users')

    do_define_attributes

    def create
      raise Errors::NotAuthenticated unless user
      raise Errors::NotAuthorized unless roles.admin?

      create_core
    end

    def enumerate
      raise Errors::NotAuthenticated unless user
      # TODO: stub, here to satisfy tests
      return {}.to_json
    end

    # Update operation
    #
    # @param [String] guid The GUID of the object to update.
    def update(guid)
      obj = find_guid_and_validate_access(:update, guid)

      json_msg = self.class::UpdateMessage.decode(body)
      @request_attrs = json_msg.extract(:stringify_keys => true)

      logger.debug "cc.update", :guid => guid,
        :attributes => request_attrs

      raise InvalidRequest unless request_attrs

      model.db.transaction do
        obj.lock!
        was_admin = obj.admin?
        obj.update_from_hash(request_attrs)
        if obj.admin? != was_admin # there has been a change in admin status
          scim_user = {'id' => guid}
          StackatoUserCreation::ADMIN_GROUPS.each do |group|
            if obj.admin?
              add_user_to_group(scim_user, group)
            else
              remove_user_from_group(scim_user, group)
            end
          end
        end
      end

      [HTTP::OK, serialization.render_json(self.class, obj, @opts)]
    end

    def delete(guid)

      obj = find_guid_and_validate_access(:delete, guid)

      model.db.transaction do
        obj.destroy
        scim_client.delete(:user, guid)
      end

      [HTTP::OK]
    end
    
  end
end
