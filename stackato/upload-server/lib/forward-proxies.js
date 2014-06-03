/**
 * Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.
 */

'use strict';

var Http = require('http'),
    HttpProxy = require('http-proxy'),
    Request = require('request');

/* Upstream cloud controller unix domain socket path */
var ccSocket = process.env.ccSocket;

/* Non upload request forwarder */
var proxy = HttpProxy.createProxyServer({
    agent: new Http.Agent()
});

proxy.on('error', function (e) {
    console.error('Error proxying to the cloud controller: ' + e);
});

module.exports = {

    /**
     * Proxies droplet uploads from stagers to the CC. Droplet zipfile should
     * already be on disk.
     * @param {Object} req - Http.IncomingRequest
     * @param {Object} res - Http.OutgoingResponse
     * @param {String} filename - The full file path to the uploaded droplet zip
     */
    proxyDropletUpload: function (req, res, filename) {
        Request.post({
            uri: 'unix://' + ccSocket + req.url,
            headers: {
                authorization: req.headers.authorization,
                host: req.headers.host
            },
            form: {
                droplet_path: filename
            }
        })
        .on('error', function (err) {
            req.log.error('Error proxying droplet upload request to the cloud controller: %s', err);
        })
        .pipe(res);
    },

    /**
     * Pass through proxy for all non-intercepable uploads
     * @param {Object} req - Http.IncomingRequest
     * @param {Object} res - Http.OutgoingResponse
     */
    proxyToCloudController: function (req, res) {
        proxy.web(req, res, {
            target: {
                socketPath: ccSocket
            }
        });
    },

    /**
     * Makes a modified request to upload the app zipfile, which is already on disk
     * at this point.
     * @param {Object} req - Http.IncomingRequest
     * @param {Object} res - Http.OutgoingResponse
     * @param {String} filepath - The full file path to the uploaded client zip
     * @param {String} filename - The file name as originally specified by the client
     * @param {Array} resources - An array of filename/sha1 mappings to resources
     * @param {String} type - The type of resource being proxied ('application' | 'buildpack')
     */
    proxyUploadToCloudController: function (req, res, filepath, filename, resources, type) {

        var form = {};
        form[type + '_path'] = filepath;
        form[type + '_name'] = filename;

        if (resources) {
            form.resources = resources;
        }

        Request.put({
            uri: 'unix://' + ccSocket + req.url,
            headers: {
                authorization: req.headers.authorization,
                host: req.headers.host
            },
            form: form
        })
        .on('error', function (err) {
            req.log.error('Error proxying request to the cloud controller: %s', err);
        })
        .pipe(res);
    }
};
