/**
 * Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.
 */

'use strict';

var Log = require('log'),
    Package = require('./package'),
    Path = require('path'),
    Config = require('./lib/config'),
    ClusterMaster = require('cluster-master');

/* Logger for the cluster master */
var logLevel = process.env.UPLOAD_LOG_LEVEL || 'info';
var log = new Log(logLevel);
/* Worker process environment */
var workerEnv = Config;

/* Handles messages from the worker processes */
var handleWorkerMessage = function (msg) {
    console.log('Received message from the worker process %s %j'
               , this.uniqueID
               , msg);
};

/* Worker process manager */
ClusterMaster({
    env: workerEnv,
    exec: Path.join(__dirname, 'worker.js'),
    onMessage: handleWorkerMessage,
    repl: false,
    debug: false,
});

log.info('Application uploads are sent to: ' + workerEnv.uploadAppBitsDir);
log.info('Staging bits uploads are sent to: ' + workerEnv.uploadStagingBitsDir);
log.info('All other requests are forwarded to: ' + workerEnv.ccSocket);
log.info('Stackato file upload server v%s is listening for requests on port %s', Package.version, workerEnv.listenPort);
