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
var uploadBuildpackBitsDir = process.env.uploadAppBitsDir;

new Mkdirp(uploadBuildpackBitsDir, function (err) {
    if (err) { throw err; }
});

module.exports = function(req, res) {

    var buildpackFilePath,
        buildpackFileName,
        called = false,
        error = false,
        resources;

    var busboy = new Busboy({
        headers: req.headers,
        limits: Common.uploadLimits
    });

    if (req.method === 'POST' || req.method === 'PUT') {
        busboy.on('file', function (fieldname, file, filename, encoding, mimetype) {
            if (fieldname === 'buildpack') {
                buildpackFilePath = Path.join(uploadBuildpackBitsDir, new Date().getTime() + '-' + Path.basename(fieldname));
                buildpackFileName = filename;
                var buildpackWriteStream = Fs.createWriteStream(buildpackFilePath);
                file.pipe(buildpackWriteStream);
                file.on('end', function () {
                    buildpackWriteStream.end();
                    if (file.truncated) {
                        res.statusCode = 413;
                        res.end('HTTP Error 413: Request entity too large');
                        error = true;
                    }
                });
            }
        });
        busboy.on('finish', function () {
            if (error) { return; }
            if (!called) { // bug, seems to emit twice
                if (buildpackFilePath) {
                    req.log.info('Handled buildpack upload for filename %s stored @ file: %s', buildpackFileName, buildpackFilePath);
                    ForwardProxies.proxyUploadToCloudController(req, res, buildpackFilePath, buildpackFileName, resources, {}, 'buildpack');
                    called = true;
                } else {
                    req.log.error('Cannot process buildpack upload request: filepath attribute is not not mapped');
                }
            }
        });
        return req.pipe(busboy);
    } else {
        ForwardProxies.proxyToCloudController(req, res);
    }
};
