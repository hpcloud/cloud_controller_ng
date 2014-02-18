/**
 * Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.
 */

'use strict';

var Async = require('async');

var enabledMiddleware = [];

module.exports = {
    use: function (name) {
        enabledMiddleware.push(require('./' + name));
    },
    request: function (req, res, done) {
        Async.eachSeries(enabledMiddleware,
            function (middleware, next) {
                middleware(req, res, next);
            },
            function (err) {
                if (err) {
                    console.error(err);
                }
                done(err);
            }
        );
    }
};
