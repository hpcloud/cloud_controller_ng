require 'jobs/cc_job'
require 'jobs/runtime/app_bits_packer'
require 'jobs/runtime/app_bits_copier'
require 'jobs/runtime/app_events_cleanup'
require 'jobs/runtime/app_usage_events_cleanup'
require 'jobs/runtime/blobstore_delete'
require 'jobs/runtime/blobstore_upload'
require 'jobs/runtime/buildpack_installer'
require 'jobs/runtime/droplet_deletion'
require 'jobs/runtime/droplet_upload'
require 'jobs/runtime/events_cleanup'
require 'jobs/runtime/model_deletion'
require 'jobs/runtime/legacy_jobs'
require 'jobs/runtime/failed_jobs_cleanup'
require 'jobs/runtime/pending_packages_cleanup'
require 'jobs/v3/package_bits'
require 'jobs/v3/droplet_upload'
require 'jobs/runtime/stackato/docker_registry_cleanup'
require 'jobs/runtime/stackato/monitor'
require 'jobs/enqueuer'
require 'jobs/wrapping_job'
require 'jobs/exception_catching_job'
require 'jobs/request_job'
require 'jobs/timeout_job'
require 'jobs/local_queue'
require 'jobs/delete_action_job'

require "kato/local/node"

class LocalQueue < Struct.new(:config)
  NODE_ID = Kato::Local::Node.get_local_node_id
  def to_s
    "cc-" + NODE_ID
  end
end


