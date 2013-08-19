# TODO - Enforce sane numbering of these errors.
# TODO - Check for v2 conflicts in VCAP::Errors

class CloudError < StandardError
  attr_reader :status, :value, :error_code
  def initialize(info, *args)
    @error_code, @status, msg = *info
    @message = sprintf(msg, *args)
    super(@message)
  end

  def to_json(options = nil)
    Yajl::Encoder.encode({:code => @error_code, :description => @message})
  end

  CONTACT_ADMIN = "Please contact your cloud administrator."

  HTTP_BAD_REQUEST           = 400
  HTTP_FORBIDDEN             = 403
  HTTP_NOT_FOUND             = 404
  HTTP_INTERNAL_SERVER_ERROR = 500
  HTTP_NOT_IMPLEMENTED       = 501
  HTTP_BAD_GATEWAY           = 502
  HTTP_SERVICE_UNAVAILABLE   = 503

  # HTTP / JSON errors
  BAD_REQUEST           = [100, HTTP_BAD_REQUEST, "Bad request"]
  DATABASE_ERROR        = [101, HTTP_INTERNAL_SERVER_ERROR, "Error talking with the database"]
  LOCKING_ERROR         = [102, HTTP_BAD_REQUEST, "Optimistic locking failure"]
  SYSTEM_ERROR          = [111, HTTP_INTERNAL_SERVER_ERROR, "System Exception Encountered"]
  MAINTENANCE_MODE      = [112, HTTP_SERVICE_UNAVAILABLE, "Stackato down for maintenance"]
  NEED_MAINTENANCE_MODE = [403, HTTP_SERVICE_UNAVAILABLE, "Stackato must be in maintenance mode to perform this action"]

  # User-level errors
  FORBIDDEN       = [200, HTTP_FORBIDDEN, "Operation not permitted"]
  USER_NOT_FOUND  = [201, HTTP_FORBIDDEN, "User not found"]
  GROUP_NOT_FOUND = [201, HTTP_FORBIDDEN, "Group not found"]
  HTTPS_REQUIRED  = [202, HTTP_FORBIDDEN, "HTTPS required"]
  GROUP_MISSING   = [203, HTTP_INTERNAL_SERVER_ERROR, "A group that should exist on the system is missing"]
  INVALID_REFERER = [204, HTTP_FORBIDDEN, "Invalid HTTP Referer header"]

  # Application-level errors
  APP_INVALID            = [300, HTTP_BAD_REQUEST, "Invalid application description"]
  APP_NOT_FOUND          = [301, HTTP_NOT_FOUND, "Application not found"]
  APP_NO_RESOURCES       = [302, HTTP_NOT_FOUND, "Couldn't find a place to run an app"]
  APP_FILE_NOT_FOUND     = [303, HTTP_NOT_FOUND, "Could not find : '%s'"]
  APP_FILE_FORBIDDEN     = [11112, HTTP_FORBIDDEN, "Forbidden : '%s'"]
  APP_INSTANCE_NOT_FOUND = [304, HTTP_BAD_REQUEST, "Could not find instance: '%s'"]
  APP_STOPPED            = [305, HTTP_BAD_REQUEST, "Operation not permitted on a stopped app"]
  APP_FILE_ERROR         = [306, HTTP_INTERNAL_SERVER_ERROR, "Error retrieving file '%s'%s"]
  APP_RUN_ERROR          = [306, HTTP_INTERNAL_SERVER_ERROR, "Error running cmd '%s'%s"]
  APP_INVALID_RUNTIME    = [307, HTTP_BAD_REQUEST, "Invalid runtime specification [%s] for framework: '%s'"]
  APP_INVALID_FRAMEWORK  = [308, HTTP_BAD_REQUEST, "Invalid framework description: '%s'"]
  APP_DEBUG_DISALLOWED   = [309, HTTP_BAD_REQUEST, "Cloud controller has disallowed debugging."]

  # This error is shown on the client during push/update. The %s will
  # contain the entire staging log including a brief description of
  # the error. Hence, it is unnecessary to prefix it further with a
  # similar message.
  APP_STAGING_ERROR = [310, HTTP_INTERNAL_SERVER_ERROR, "%s"]

  # Bits
  RESOURCES_UNKNOWN_PACKAGE_TYPE = [400, HTTP_BAD_REQUEST, "Unknown package type requested: \"%\""]
  RESOURCES_MISSING_RESOURCE     = [401, HTTP_BAD_REQUEST, "Could not find the requested resource"]
  RESOURCES_PACKAGING_FAILED     = [402, HTTP_INTERNAL_SERVER_ERROR, "App packaging failed: '%s'"]

  # Services
  SERVICE_NOT_FOUND         = [500, HTTP_NOT_FOUND, "Service not found"]
  BINDING_NOT_FOUND         = [501, HTTP_NOT_FOUND, "Binding not found"]
  TOKEN_NOT_FOUND           = [502, HTTP_NOT_FOUND, "Token not found"]
  SERVICE_GATEWAY_ERROR     = [503, HTTP_BAD_GATEWAY, "Unexpected response from service gateway. #{CONTACT_ADMIN}"]
  ACCOUNT_TOO_MANY_SERVICES = [504, HTTP_FORBIDDEN, "Too many Services provisioned: %s, you're allowed: %s"]
  EXTENSION_NOT_IMPL        = [505, HTTP_NOT_IMPLEMENTED, "Service extension %s is not implemented."]
  UNSUPPORTED_VERSION       = [506, HTTP_NOT_FOUND, "Unsupported service version %s."]
  SDS_ERROR                 = [507, HTTP_INTERNAL_SERVER_ERROR, "Get error from serialization_data_server: '%s'"]
  SDS_NOT_FOUND             = [508, HTTP_INTERNAL_SERVER_ERROR, "No available active serialization data server"]

  # Account Capacity
  ACCOUNT_NOT_ENOUGH_MEMORY = [600, HTTP_FORBIDDEN, "Not enough memory capacity, you're allowed: %s"]
  ACCOUNT_APPS_TOO_MANY     = [601, HTTP_FORBIDDEN, "Too many applications: %s, you're allowed: %s"]
  ACCOUNT_APP_TOO_MANY_URIS = [602, HTTP_FORBIDDEN, "Too many URIs: %s, you're allowed: %s"]

  # URIs
  URI_INVALID       = [700, HTTP_BAD_REQUEST, "Invalid URI: \"%s\""]
  URI_ALREADY_TAKEN = [701, HTTP_BAD_REQUEST, "The URI: \"%s\" has already been taken or reserved"]
  URI_NOT_ALLOWED   = [702, HTTP_FORBIDDEN, "External URIs are not enabled for this account"]

  # Staging
  STAGING_TIMED_OUT = [800, HTTP_INTERNAL_SERVER_ERROR, "Timed out waiting for staging to complete"]
  STAGING_FAILED    = [801, HTTP_INTERNAL_SERVER_ERROR, "Staging failed"]

  # Web Console errors
  CONSOLE_GENERIC     = [10000, HTTP_INTERNAL_SERVER_ERROR, "Console Backend Generic Error: %s"]
  CONSOLE_UNLICENSED  = [10001, HTTP_FORBIDDEN, "Micro cloud is not setup with a license"]
  CONSOLE_BAD_REQUEST = [10002, HTTP_BAD_REQUEST, "Bad Request: %s"]

  # Cluster/Node errors
  CLUSTER_NODE_UNREACHABLE = [11000, HTTP_INTERNAL_SERVER_ERROR, "Cluster node unreachable : %s"]

  BAD_REQUEST_GENERIC = [22000, HTTP_BAD_REQUEST, "Bad request: %s"]
  FORBIDDEN_GENERIC   = [22002, HTTP_FORBIDDEN, "Forbidden: %s"]

  ACCOUNT_APP_TOO_MANY_DRAINS = [22001, HTTP_FORBIDDEN, "Too many drains added to this app: %s, you're allowed: %s"]
  TOO_MANY_DRAINS = [22002, HTTP_FORBIDDEN, "No more drains can be added; contact your cluster admin."]

  # Aok
  AOK_BASE_CODE        = 13000
  AOK_GATEWAY_ERROR    = [AOK_BASE_CODE+503, HTTP_BAD_GATEWAY, "Unable to contact the login server. #{CONTACT_ADMIN}"]
  AOK_GENERIC_ERROR    = [AOK_BASE_CODE+500, HTTP_INTERNAL_SERVER_ERROR, "Login server encountered an error: %s"]
  AOK_ENTITY_NOT_FOUND = [AOK_BASE_CODE+404, HTTP_NOT_FOUND, "Login server could not find the requested entity."]
  AOK_FORBIDDEN        = [AOK_BASE_CODE+403, HTTP_FORBIDDEN, "Forbidden by login server."]
  # The following error ends up being displayed in the Stackato client when someone has attempted to log in
  # with a username/pw when they need to be using openid instead.
  AOK_DIRECT_LOGIN_DISABLED = [AOK_BASE_CODE+444, HTTP_FORBIDDEN, "You must log in via the web interface. %s"]

  # See bug 96956
  def ==(other)
    if self.class == other.class
      return error_code == other.error_code
    elsif other.kind_of? Array
      # allows for matching e.g. $! == CONSOLE_GENERIC
      return error_code == other.first
    else
      return false
    end
  end

end
