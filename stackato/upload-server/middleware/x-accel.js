/**
 * Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.
 */

'use strict';

var Fs = require('fs'),
    Common = require('../lib/common');

/* A fairly crude implementation of Nginx's X-Accel-Redirect feature.
 * Node.js doesn't have a native sendfile() syscall so performance
 * will never be on par in userspace, but at least we can ensure the
 * entire file is never read into memory via streaming from disk.
 */
module.exports = function (req, res, next) {

    if (req.method !== 'GET') {
        return next();
    }

    res._realSetHeader = res.setHeader;
    res._realEnd = res.end;
    res._realWriteHead = res.writeHead;

    var XAccelRedirect = false;
    var XAccelRedirectPath = null;

    res.setHeader = function (name, value) {
        if (name.match(/X-Accel-Redirect/i)) {
            XAccelRedirect = true;
            XAccelRedirectPath = value;
            return;
        }
        res._realSetHeader(name, value);
    };

    res.writeHead = function (statusCode, reason, headers) {
        if (!XAccelRedirect) {
            res._realWriteHead(statusCode, reason, headers);
        } else {
            res.writeHead = res._realWriteHead;
        }
    };

    res.end = function (chunk, encoding) {
        res.end = res._realEnd;

        if (XAccelRedirect) {
            var filePath = (function () {
                var urlMatch = XAccelRedirectPath.match(/^\/(cc-packages|cc-droplets)/);
                if (!urlMatch) {
                    return;
                }
                if (urlMatch[1] === 'cc-packages') {
                    return XAccelRedirectPath.replace(urlMatch[0], Common.ccPackagesDir);
                } else if  (urlMatch[1] === 'cc-droplets') {
                    return XAccelRedirectPath.replace(urlMatch[0], Common.ccDropletsDir);
                }
            })();

            if (!filePath) {
                var errMsg = 'No mapping configured for X-Accel-Redirect URI: ' + XAccelRedirectPath;
                req.log.warning(errMsg);
                res.statusCode = 404;
                res.end(errMsg);
                return;
            }

            Fs.exists(filePath, function (exists) {
                if (!exists) {
                    var errMsg = 'X-Accel mapping, file does not exist at: ' + filePath;
                    req.log.warning(errMsg);
                    res.statusCode = 404;
                    res.end(errMsg);
                    return;
                } else {
                    Fs.stat(filePath, function(err,stats) {
                        var fileStream = Fs.createReadStream(filePath);

                        res.writeHead(200, {
                            'Content-Type' : 'application/octet-stream',
                            'Content-Length': stats.size
                        });

                        fileStream.on('error', function (error) {
                            req.log.error(error);
                            if (!res.headersSent) {
                                res.writeHead(500);
                                res.end(error);
                            }
                        });
                        fileStream.on('end', function () {
                            req.log.info('Handled X-Accel-Redirect for path: %s -> ', XAccelRedirectPath, filePath);
                            res.end();
                        });
                        fileStream.pipe(res);
                    });
                }
            });
        } else {
            res._realEnd(chunk, encoding);
        }
    };
    next();
};
