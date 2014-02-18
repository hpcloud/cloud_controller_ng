/**
 * Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.
 */

'use strict';

var Log = require('log'),
    Package = require('./package'),
    ClusterMaster = require('cluster-master');

/* Logger for the cluster master */
var log_level = process.env.UPLOAD_LOG_LEVEL || 'info';
var log = new Log(log_level);

/* Worker process environment */
var workerEnv = {

    /* HTTP listen port */
    listen_port: 8181,

    /* Upstream cloud controller unix domain socket path */
    cc_socket: '/var/stackato/sys/run/cloud_controller_ng/cloud_controller.sock',

    /* Base directory for storing uploaded app bits */
    upload_app_bits_dir: '/var/stackato/data/cloud_controller_ng/tmp/uploads',

    /* Base directory for storing uploaded staging/buildpack bits */
    upload_staging_bits_dir: '/var/stackato/data/cloud_controller_ng/tmp/staged_droplet_uploads',

    /* Default logging level */
    log_level:  log_level,

    /* HTTP access log file path */
    access_log: '/s/logs/cloud_controller_uploads_access.log'
};

/* Handles messages from the worker processes */
var handleWorkerMessage = function (msg) {
    console.log('Received message from the worker process %s %j'
               , this.uniqueID
               , msg);
};

/* Worker process manager */
ClusterMaster({
    env: workerEnv,
    exec: 'worker.js',
    onMessage: handleWorkerMessage,
    repl: false,
    debug: false,
});

log.info('Application uploads are sent to: ' + workerEnv.upload_app_bits_dir);
log.info('Staging bits uploads are sent to: ' + workerEnv.upload_staging_bits_dir);
log.info('All other requests are forwarded to: ' + workerEnv.cc_socket);
log.info('Stackato file upload server v%s is listening for requests on port %s', Package.version, workerEnv.listen_port);
