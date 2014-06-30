/**
 * Copyright (c) ActiveState 2014 - ALL RIGHTS RESERVED.
 */

'use strict';

module.exports =  {
    /* File upload limits */
    uploadLimits: {
        fields: 200,
        fieldSize: process.env.UPLOAD_FIELDSIZE_LIMIT || 20971520, // 20MB
        files: 100,
        fileSize: process.env.UPLOAD_FILE_LIMIT || 1610612736, // 1.5GB
        parts: 300
    },
    /* buildpack caches / app upload bits */
    ccPackagesDir: '/home/stackato/stackato/data/cc-packages',
    /* staged droplets */
    ccDropletsDir: '/home/stackato/stackato/data/cc-droplets'
};
