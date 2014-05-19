/**
 * Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.
 */

'use strict';

var Fs = require('fs'),
    Path = require('path'),
    Busboy = require('busboy'),
    Common = require('./common'),
    ForwardProxies = require('./forward-proxies'),
    Mkdirp = require('mkdirp');

/* Base directory for storing uploaded files */
var uploadAppBitsDir = process.env.uploadAppBitsDir;

Mkdirp(uploadAppBitsDir, function (err) {
    if (err) { throw err; }
});

module.exports = function(req, res) {

    var applicationFilePath,
        applicationFileName,
        called = false,
        error = false,
        resources;

    var busboy = new Busboy({
        headers: req.headers,
        limits: Common.uploadLimits
    });

    if (req.method === 'POST' || req.method === 'PUT') {
        busboy.on('file', function (fieldname, file, filename, encoding, mimetype) {
            if (fieldname === 'application') {
                applicationFilePath = Path.join(uploadAppBitsDir, new Date().getTime() + '-' + Path.basename(fieldname));
                applicationFileName = filename;
                var appWriteStream = Fs.createWriteStream(applicationFilePath);
                file.pipe(appWriteStream);
                file.on('end', function () {
                    appWriteStream.end();
                    if (file.truncated) {
                        res.statusCode = 413;
                        res.end('HTTP Error 413: Request entity too large');
                        error = true;
                    }
                });
            }
        });
        busboy.on('field', function (fieldname, val, valTruncated, keyTruncated) {
            if (fieldname === 'resources') { resources = val; }
        });
        busboy.on('finish', function () {
            if (error) { return; }
            if (!called) { // bug, seems to emit twice
                if (applicationFilePath && resources) {
                    req.log.info('Handled app bits upload for filename %s stored @ file: %s', applicationFileName, applicationFilePath);
                    ForwardProxies.proxyUploadToCloudController(req, res, applicationFilePath, resources);
                    called = true;
                } else {
                    req.log.error('Cannot process upload request: Resources / filepath attributes are not mapped');
                }
            }
        });
        return req.pipe(busboy);
    } else {
        ForwardProxies.proxyToCloudController(req, res);
    }
};
