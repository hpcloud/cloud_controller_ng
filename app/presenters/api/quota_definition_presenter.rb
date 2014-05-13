require_relative 'api_presenter'

class QuotaDefinitionPresenter < ApiPresenter
  def entity_hash
    {
      name: @object.name,
      non_basic_services_allowed: @object.non_basic_services_allowed,
      total_services: @object.total_services,
      memory_limit: @object.memory_limit,
<<<<<<< HEAD
      trial_db_allowed: @object.trial_db_allowed,
      allow_sudo: @object.allow_sudo
=======
      trial_db_allowed: false
>>>>>>> upstream/master
    }
  end
end
