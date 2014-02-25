require "uaa/token_issuer"
require "uaa/scim"
require_relative 'stackato_user_creation'
module VCAP::CloudController
  class StackatoUsersController < RestController::ModelController
    include StackatoUserCreation
    path_base('stackato/users')

    do_define_attributes

    def create
      raise Errors::NotAuthenticated unless user
      raise Errors::NotAuthorized unless roles.admin?
      check_maintenance_mode
      create_core
    end

    def enumerate
      raise Errors::NotAuthenticated unless user
      query_json = params["q"] || ''
      query = QueryUserMessage.decode(query_json)
      attributes_to_request = query.attributes
      guids_to_request = []

      if user.admin?
        # Admins can get info on all users without restrictions
        guids_to_request = query.guids
      else
        # Normal users can only get info on users that belong to the same org(s) as them
        # XXX: This could be made more efficient. Query DB for this information
        all_guids = user.organizations.collect(&:user_guids).flatten.uniq
        guids_to_request = query.guids & all_guids

        # Handle the case where a user doesn't belong to any orgs and is fetching their own info
        if query.guids.include? user.guid
          guids_to_request << user.guid
        end

        # Work around for the case where guids_to_request is empty which would result in all users being returned
        if guids_to_request.length == 0
          guids_to_request << "X_NOT_A_REAL_GUID_X"
        end
      end

      result = scim_client.query(
        :user,
        'attributes' => attributes_to_request.join(','),
        'filter' => guids_to_request.collect{|guid| %Q!id eq #{guid.inspect}!}.join(' or ')
        )
      # XXX Hack alert! Using a private method in the SCIM client to correct key case
      result = @scim_client.method(:force_case).call(Hash[result])
      [HTTP::OK, result.to_json]
    end

    # Update operation
    #
    # @param [String] guid The GUID of the object to update.
    def update(guid)
      check_maintenance_mode
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
      check_maintenance_mode
      obj = find_guid_and_validate_access(:delete, guid)

      model.db.transaction do
        obj.destroy
        scim_client.delete(:user, guid)
      end

      [HTTP::OK]
    end

    class QueryUserMessage < JsonMessage

      def self.decode json
        #logger.debug "JSON to decode: #{json.inspect}"
        begin
          dec_json = Yajl::Parser.parse(json)
        rescue => e
          raise ParseError, e.to_s
        end
        #logger.debug "Downcased json: #{dec_json.inspect}"
        from_decoded_json(dec_json)
      end

      required :attributes, [String]
      required :guids,      [String]

    end

    define_messages
    define_standard_routes
  end
end
