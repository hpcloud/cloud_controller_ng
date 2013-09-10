
require "kato/config"
require "kato/local/util"

module VCAP::CloudController
  class StackatoSetupController < RestController::Base
    allow_unauthenticated_access

    # One-time setup done without any authen/authz
    # 1. Change the UNIX password (from the default 'stackato')
    # 2. Create the first user
    # 3. Mark this user as an admin
    #    a. in the YAML file
    #    b. in the internal admins list
    def setup
      user = nil
      if Kato::Config.get("cluster", "license")
        raise Errors::StackatoLicenseAlreadySetup.new
      elsif Kato::Config.get("aok", "enabled") && !aok_users_enabled?
        raise Errors::StackatoConsoleSetupRequiresAokBuiltinUserDB.new

      # Validation
      # TODO: Move validation to the user model & determine 
      # what we can really enforce in light of AOK
      elsif not (params[:email])
        raise Errors::StackatoSetupEmailRequired.new
      elsif params[:email].length < USERNAME_MIN_SIZE
        raise Errors::StackatoSetupEmailMinLength.new(USERNAME_MIN_SIZE)
      elsif params[:password] && params[:password].length <= 4 or
          (params[:unix_password] and params[:unix_password].length <= 4)
        raise Errors::StackatoSetupPasswordMinLength.new(4)
      else

        run_cmd('sudo -k', "failed to reset sudo password cache")

        # TODO:Stackato: Define transaction correctly
        #Sequel::Model.db.transaction do
        begin
          logger.info("SETUP: creating admin user #{params[:email]}")

          # TODO:Stackato: Figure out how to create user. Should we
          #                be creating a user here?
          #user = create_user(params[:email], params[:password], true, :check_admin => false)
          # ???
          #user = Models::User.create(
          #  :id => params[:email], :provider => provider
          #)

          # Change the unix password, assuming 'stackato' as the current password
          if params[:unix_password] and Kato::Local::Util.password_is_stackato?
            logger.info("SETUP: changing unix user password")
            # passwords may contain shell meta-characters; so write to a
            # tmp file and then pipe its contents to chpasswd
            passwdfile = '/tmp/cc-setup-p-tmp'
            File.open(passwdfile, 'w') do |f|
              f.puts("stackato:#{params[:unix_password]}")
            end
            cmd = "echo 'stackato' | sudo -S sh -c \"cat #{passwdfile} | chpasswd\""
            run_cmd(cmd, "failed to change stackato unix password")
            File.delete(passwdfile)
          end

          # from this point, only an admin should be able to create new users
          logger.info("SETUP: disabling user registration")
          Kato::Config.set("cloud_controller", "allow_registration", false)

        end # transaction

        logger.info("SETUP: storing the license key in config")
        Kato::Config.set("cluster", "license", "type: microcloud")

        Yajl::Encoder.encode(UserToken.create(user.email))
      end
    end

    # Run a command and report to log, and back to caller.
    # The STDOUT of the cmd will only be printed to the log.
    @private
    def run_cmd(cmd, errmsg)
      output = `#{cmd}`
      if not $?.success?
        logger.info("SETUP: #{errmsg}: #{output}")
        # TODO:Stackato: Handle in a more ccng way
        #raise CloudError.new(CloudError::CONSOLE_GENERIC, errmsg)
      end
    end

    post "/v2/stackato/license", :setup

  end
end
