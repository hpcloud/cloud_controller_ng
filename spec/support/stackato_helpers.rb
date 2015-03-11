# Spec support required for Stackato specific modifications

module StackatoHelpers

  def stub_stackato_additions
    stub_username_caching
  end

  # Usernames are cached within cc_ng; however this requires a scim call on before_save and breaks tests
  # See https://github.com/ActiveState/cloud_controller_ng/commit/03cc2ee68abba0821c6bcbce19c616dc564137aa
  # for where this was introduced.
  def stub_username_caching
    allow_any_instance_of(VCAP::CloudController::User).to receive(:cache_username).and_return('')
  end
end