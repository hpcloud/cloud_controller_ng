/**
 * Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.
 */

'use strict';

/* Staged bits handler */

var Fs = require('fs'),
    Path = require('path'),
    Busboy = require('busboy'),
    Common = require('./common'),
    ForwardProxies = require('./forward-proxies'),
    Mkdirp = require('mkdirp');

/* Base directory for storing uploaded staging/buildpack bits */
var uploadStagingBitsDir = process.env.upload_staging_bits_dir;

Mkdirp(uploadStagingBitsDir, function (err) {
    if (err) { throw err; }
});

module.exports = function(req, res) {

    var called = false,
        dropletFilePath,
        dropletFileName,
        error = false;

    var busboy = new Busboy({
        headers: req.headers,
        limits: Common.uploadLimits
    });

    if (req.method === 'POST' || req.method === 'PUT') {
        busboy.on('file', function (fieldname, file, filename, encoding, mimetype) {
            if (fieldname === 'upload[droplet]') {
                dropletFilePath = Path.join(uploadStagingBitsDir, new Date().getTime() + '-' + filename);
                dropletFileName = filename;
                var stagingWriteStream = Fs.createWriteStream(dropletFilePath);
                file.pipe(stagingWriteStream);
                file.on('end', function () {
                    stagingWriteStream.end();
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
                if (dropletFilePath) {
                    req.log.info('Handled droplet upload for droplet %s stored @ file: %s', dropletFileName, dropletFilePath);
                    ForwardProxies.proxyDropletUpload(req, res, dropletFilePath);
                    called = true;
                } else {
                    req.log.error('Cannot process upload request: droplet_path is missing in form');
                    ForwardProxies.proxyToCloudController(req, res);

                }
            }
        });
        return req.pipe(busboy);
    } else {
        ForwardProxies.proxyToCloudController(req, res);
    }
};

