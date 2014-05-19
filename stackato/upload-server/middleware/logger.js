/**
 * Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.
 */

'use strict';

var Fs = require('fs'),
    Log = require('log');

/* Default logging level */
var logLevel = process.env.log_level;

/* HTTP access logger */
var accessLog = new Log(logLevel, Fs.createWriteStream(process.env.access_log, {
    flags: 'a'
}));

/* Console logger */
var log = new Log(logLevel);


/**
 * Log every request on finish, and each req/res on error. Additionally attach
 * logging functions for use with other middlewares / routing functions.
 * @param {Object} req - HTTP.incomingRequest
 * @param {Object} res - HTTP.outgoingResponse
 */
module.exports = function (req, res, next) {
    var remoteAddr = req.connection.remoteAddress;

    req.on('error', function (err) {
        accessLog.error('Request error: %s - %s - %s - %s', err, remoteAddr, req.method, req.url);
    });

    res.on('error', function (err) {
        accessLog.error('Response error: %s - %s - %s - %s', err, remoteAddr, req.method, req.url);
    });

    res.on('finish', function () {
        accessLog.info('%s - %s - %s - %s', remoteAddr, req.method, req.url, JSON.stringify(req.headers));
    });

    req.log = log;
    req.accessLog = accessLog;

    next();
};
