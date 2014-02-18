/**
 * Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.
 */

'use strict';

/* Disable response Timeouts */
module.exports = function(req, res, next) {
    res.setTimeout(0);
    next();
};
