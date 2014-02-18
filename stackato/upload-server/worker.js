/**
 * Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.
 */

'use strict';

var Log = require('log'),
    Http = require('http'),
    Router = require('router'),
    MiddleWare = require('./middleware'),
    AppUpload = require('./lib/app-bits-upload'),
    DropletUpload = require('./lib/droplet-bits-upload'),
    ForwardProxies = require('./lib/forward-proxies'),
    Pong = require('./lib/pong');

/* HTTP listen port */
var listenPort = process.env.listen_port;

/* Default logging level */
var logLevel = process.env.log_level;

/* console logger */
var log = new Log(logLevel);

/* HTTP Route dispatcher */
var router = new Router();

/* HTTP middleware */
MiddleWare.use('logger');
MiddleWare.use('timeouts');
MiddleWare.use('x-accel');

/* Client app bit uploads */
router.put('/v2/apps/*/bits', AppUpload);
router.post('/v2/apps/*/bits', AppUpload);

/* Internal droplet & buildpack cache uploads */
router.put('/staging/(buildpack_cache|droplets)/*/upload', DropletUpload);
router.post('/staging/(buildpack_cache|droplets)/*/upload', DropletUpload);

/* Health check */
router.get('/upload-server/ping', Pong);

/**
 * The main HTTP server
 *
 * The busboy module reads the multipart form via piping in the original request,
 * and from the events it emits we construct a new request by:
 * a) writing the application zipfile to disk
 * b) passing through the `resources` field
 * c) proceeds to construct a new request to the CC with a) & b).
 * @param {Object} req - Http.IncomingRequest
 * @param {Object} res - Http.OutgoingResponse
 */
Http.createServer(function (req, res) {
    MiddleWare.request(req, res, function (err) {
        if (err) {
            log.error('Error processing middleware: %s', err);
            return;
        }
        router(req, res, function () {
            /* No route matched */
            ForwardProxies.proxyToCloudController(req, res);
        });
    });
})
.on('error', function (e) {
    log.error('Error serving request: ', e);
})
.listen(listenPort, function (){
    log.debug('alive');
})
.setTimeout(0);
