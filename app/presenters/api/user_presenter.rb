require_relative 'api_presenter'

class UserPresenter < ApiPresenter
  def entity_hash
    {
        admin: @object.admin?,
        active: @object.active?,
        default_space_guid: @object.default_space_guid
    }
  end

  def metadata_hash
    super.merge(logged_in_at: @object.logged_in_at)
  end
end
