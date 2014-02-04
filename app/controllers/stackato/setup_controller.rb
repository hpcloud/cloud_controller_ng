
require "kato/config"
require "kato/local/util"
require "controllers/stackato/stackato_user_creation"

module VCAP::CloudController
  rest_controller :StackatoSetup do
    allow_unauthenticated_access
    include StackatoUserCreation
    do_define_attributes true
    define_messages

    def setup
      create_core(:is_first_user_setup => true)
    end; post "/v2/stackato/firstuser", :setup
  end
end
