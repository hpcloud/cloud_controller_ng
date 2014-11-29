require "jobs/runtime/app_bits_packer"
require "jobs/runtime/app_events_cleanup"
require "jobs/runtime/app_usage_events_cleanup"
require "jobs/runtime/blobstore_delete"
require "jobs/runtime/blobstore_upload"
require "jobs/runtime/buildpack_installer"
require "jobs/runtime/droplet_deletion"
require "jobs/runtime/droplet_upload"
require "jobs/runtime/events_cleanup"
require "jobs/runtime/model_deletion"
require "jobs/runtime/legacy_jobs"
require "jobs/enqueuer"
require "jobs/exception_catching_job"
require "jobs/request_job"
require "jobs/timeout_job"

require "kato/local/node"

class LocalQueue < Struct.new(:config)
  NODE_ID = Kato::Local::Node.get_local_node_id
  def to_s
    "cc-" + NODE_ID
  end
end
