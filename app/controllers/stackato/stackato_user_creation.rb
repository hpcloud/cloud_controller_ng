module VCAP::CloudController
  module StackatoUserCreation
    ADMIN_GROUPS = %W{cloud_controller.admin scim.write}
    ALL_USER_GROUPS = %W{scim.read}

    # There's a model() method to do this but it breaks things
    def model; User; end

    def create_core(first_user=false)
      check_firstuser_allowed if first_user
      parameter_extraction

      # first user should be an admin
      attrs = request_attrs
      admin = attrs["admin"] || first_user
      password = attrs["password"]
      user_info = Hash.new {|h,k| h[k] = Hash.new(&h.default_proc)}
      user_info[:userName] = attrs["username"] if attrs["username"]
      user_info[:name][:givenName] = attrs["given_name"] if attrs["given_name"]
      user_info[:name][:familyName] = attrs["family_name"] if attrs["family_name"]
      if attrs["email"]
        #TODO: support multiple emails
        user_info[:emails] = [
          :value => attrs["email"]
        ]
      end
      if attrs["phone"]
        #TODO: support multiple phones
        user_info[:phoneNumbers] = [
          :value => attrs["phone"]
        ]
      end
      user_info[:password] = password if password

      logger.debug "User info to post to UAA: #{user_info.inspect}"

      before_create
      @new_user = nil
      scim_user = nil
      model.db.transaction do
        scim_user = scim_client.add :user, user_info
        logger.debug "Response from SCIM user creation: #{scim_user.inspect}"

        if admin
          ADMIN_GROUPS.each do |group|
            add_user_to_group(scim_user, group)
          end
        end
        ALL_USER_GROUPS.each do |group|
          add_user_to_group(scim_user, group)
        end

        cc_user_info = {
          'guid' => scim_user['id'],
          'admin' => admin,
          'active' => true
        }
        @new_user = model.create_from_hash(cc_user_info)

        if first_user
          firstuser(password)
        else
          validate_access(:create, @new_user, user, roles)
        end
      end

      after_create(@new_user)

      [ VCAP::RestAPI::HTTP::CREATED,
        { "Location" => "#{UsersController.path}/#{@new_user.guid}" },
        serialization.render_json(UsersController, @new_user, @opts)
      ]
    rescue CF::UAA::InvalidToken => e
      logger.error "The token for the 'cloud_controller' oauth2 client was
      not accepted by #{target}. This should never happen."
      raise e
    rescue CF::UAA::TargetError => e
      # Probably a validation error coming from the target.
      if scim_user && scim_user['id']
        logger.debug "Attempting to roll back UAA user..."
        scim_client.delete :user, scim_user['id']
      end
      return 400, e.info.to_json
    rescue Sequel::ValidationFailed => e
      logger.debug "Validation failed on the local user or org-- rolling back UAA user."
      scim_client.delete :user, scim_user['id']
      raise e
    rescue Exception => e
      begin
        logger.debug "Attempting to roll back UAA user..."
        scim_client.delete :user, scim_user['id']
      rescue Exception => uaa_rollback
        logger.debug "Rolling back UAA user failed: #{uaa_rollback.inspect}"
      end
      raise e
    end

    def firstuser(password)
      run_cmd('sudo -k', "failed to reset sudo password cache")

      # Change the unix password, assuming 'stackato' as the current password
      if Kato::Local::Util.password_is_stackato?
        logger.info("SETUP: changing unix user password")
        # passwords may contain shell meta-characters; so write to a
        # tmp file and then pipe its contents to chpasswd
        f = Tempfile.new('cc-setup-p-tmp')
        begin
          f.puts("stackato:#{password}")
          f.close
          cmd = "echo 'stackato' | sudo -S sh -c \"cat #{f.path} | chpasswd\""
          run_cmd(cmd, "failed to change stackato unix password")
        ensure
          f.close! # also unlinks
        end
      end

      # create a default org
      quota_definition = QuotaDefinition.find(:name => "paid")
      org = Organization.find_or_create(:name => request_attrs["org_name"]) do |o|
        o.quota_definition = quota_definition
      end
      org.add_user(@new_user)

      logger.info("SETUP: storing the license key in config")
      Kato::Config.set("cluster", "license", "type: microcloud")
    end

    # Run a command and report to log, and back to caller.
    # The STDOUT of the cmd will only be printed to the log.
    def run_cmd(cmd, errmsg)
      output = `#{cmd}`
      if not $?.success?
        logger.info("SETUP: #{errmsg}: #{output}")
        # TODO: make this more CCNGish?
        raise errmsg
      end
    end

    def check_firstuser_allowed
      if Kato::Config.get("cluster", "license")
        raise Errors::StackatoFirstUserAlreadySetup
      end
    end

    # TODO: This uses PUT to modify group membership. I don't believe this will work once
    # groups are big enough that they are paginated. The proper way to do this would be
    # with PATCH, but the cf-uaa-lib doesn't support patch currently and I need to move on.
    def modify_user_group_membership scim_user, group, add_or_remove=:+
      scim_group = scim_client.query( :group, 'filter' => %Q!displayName eq "#{group}"!, 'startIndex' => 1)["resources"].first
      raise "Group not found" unless scim_group
      group_guid = scim_group["id"]
      members = [{'type' => 'USER', 'value' => scim_user['id']}]
      case add_or_remove
      when :+
        # nothing to do
      when :-
        members.first['operation'] = 'delete'
      else
        raise "unknown group membership modification #{add_or_remove.inspect}."
      end
      group_info = {
        "id" => group_guid,
        "schemas" => scim_group['schemas'],
        "members" => members.uniq{|h|h['value']},
        "meta" => scim_group['meta'],
      }
      logger.debug "updated group info to put: #{group_info.inspect}"
      scim_client.patch :group, group_info
    end

    def add_user_to_group scim_user, group
      modify_user_group_membership scim_user, group, :+
    end

    def remove_user_from_group scim_user, group
      modify_user_group_membership scim_user, group, :-
    end

    def parameter_extraction
      json = body.read
      logger.debug "JSON POST body: #{json.inspect}"
      json_msg = self.class::CreateMessage.decode(json)
      @request_attrs = json_msg.extract(:stringify_keys => true)
      logger.debug "Request Atts: #{request_attrs.inspect}"
    end

    def scim_client
      return @scim_client if @scim_client
      target = Kato::Config.get("cloud_controller_ng", 'uaa/url')
      secret = Kato::Config.get("cloud_controller_ng", 'aok/client_secret')
      token_issuer =
        CF::UAA::TokenIssuer.new(target, 'cloud_controller', secret)
      token = token_issuer.client_credentials_grant
      @scim_client = CF::UAA::Scim.new(target, token.auth_header)
      return @scim_client
    end

    def self.included(base)
      base.instance_eval do
        def do_define_attributes(firstuser = false)
          # Attributes defined here control what gets extracted from
          # the POST body during CreateMessage instantiation.
          define_attributes do
            attribute :username, String
            attribute :given_name, String, :default => nil
            attribute :family_name, String, :default => nil
            attribute :email, VCAP::RestAPI::Message::EMAIL
            attribute :phone, String, :default => nil
            password_opts = {:exclude_in => [:read, :enumerate]}
            password_opts.merge!(:default => nil) unless firstuser
            attribute :password, String, password_opts
            attribute :admin, VCAP::RestAPI::Message::Boolean, :default => false
            if firstuser
              attribute :org_name, String
            end
          end
        end
      end
      base.extend ClassMethods
    end


    module ClassMethods
      def translate_validation_exception(e, attributes)
        if e.model.kind_of?(Organization)
          quota_def_errors = e.errors.on(:quota_definition_id)
          name_errors = e.errors.on(:name)
          if quota_def_errors && quota_def_errors.include?(:not_authorized)
            Errors::NotAuthorized.new(e.model.quota_definition_id)
          elsif name_errors && name_errors.include?(:unique)
            Errors::OrganizationNameTaken.new(e.model.name)
          else
            Errors::OrganizationInvalid.new(e.errors.full_messages)
          end
        else
          guid_errors = e.errors.on(:guid)
          if guid_errors && guid_errors.include?(:unique)
            Errors::UaaIdTaken.new(attributes["guid"])
          else
            Errors::UserInvalid.new(e.errors.full_messages)
          end
        end
      end
    end


  end
end
