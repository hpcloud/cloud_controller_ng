require 'actions/service_instance_delete'

module VCAP::CloudController
  class SpaceDelete
    def initialize(user_id, user_email)
      @user_id = user_id
      @user_email = user_email
    end

    def delete(dataset)
      return [UserNotFoundDeletionError.new(@user_id)] if user.nil?

      dataset.inject([]) do |errors, space_model|
        service_instance_deleter = ServiceInstanceDelete.new(
            accepts_incomplete: true,
            error_when_in_progress: true
        )
        instance_delete_errors = service_instance_deleter.delete(space_model.service_instances_dataset)
        unless instance_delete_errors.empty?
          error_message = instance_delete_errors.map(&:message).join("\n\n")
          errors.push VCAP::Errors::ApiError.new_from_details('SpaceDeletionFailed', dataset.first.name, error_message)
        end

        AppDelete.new(user, user_email).delete(space_model.app_models)

        space_model.destroy if instance_delete_errors.empty?
        errors
      end
    end

    def timeout_error(dataset)
      space_name = dataset.first.name
      VCAP::Errors::ApiError.new_from_details('SpaceDeleteTimeout', space_name)
    end

    private

    attr_reader :user_id, :user_email

    def user
      @user ||= User.find(id: @user_id)
    end
  end
end
