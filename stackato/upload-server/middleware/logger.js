/**
 * Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.
 */

'use strict';

var Fs = require('fs'),
    Log = require('log'),
    Morgan = require('morgan');

/* Default logging level */
var logLevel = process.env.logLevel;

/* HTTP access logger */
var accessLog = new Morgan({
    buffer: true,
    stream: Fs.createWriteStream(process.env.accessLog, {
        flags: 'a'
    })
});

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
        log.error('Request error: %s - %s - %s - %s', err, remoteAddr, req.method, req.url);
    });

    res.on('error', function (err) {
        log.error('Response error: %s - %s - %s - %s', err, remoteAddr, req.method, req.url);
    });

    req.log = log;
    req.accessLog = accessLog;

    accessLog(req, res, next);
};
