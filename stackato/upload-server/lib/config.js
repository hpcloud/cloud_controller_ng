/**
 * Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.
 */

var Config = {};

Config.accessLog = process.env.US_ACCESS_LOG || '/s/logs/cc_upload_server_access.log';
Config.ccSocket = process.env.US_CC_SOCKET || '/var/stackato/sys/run/cloud_controller_ng/cloud_controller.sock';
Config.listenPort = process.env.US_PORT || 8181;
Config.logLevel = process.env.LOG_LEVEL || 'info';
Config.uploadAppBitsDir = process.env.US_UPLOAD_BITS_DIR || '/var/stackato/data/cloud_controller_ng/tmp/uploads';
Config.uploadStagingBitsDir =process.env.US_STAGING_BITS_DIR || '/var/stackato/data/cloud_controller_ng/tmp/staged_droplet_uploads';

module.exports = Config;
