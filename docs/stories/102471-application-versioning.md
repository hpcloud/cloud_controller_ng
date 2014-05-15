Stackato maintains older versions of each pushed application. The main
limitation is due to the maximum number of droplets that can be stored for
the application; this setting is in the quota definition associated with the
application's organization.

Each version points to a droplet. When a droplet is finally deleted (because
the application's source code was changed and pushed, and there were already
_total_droplets_ saved droplets), its associated versions are automatically
deleted as well.

Changes to an application's configuration, but not its code, trigger creation
of a new version on the same droplet. There is no limit to the number of
these configuration-only versions that can be stored.

The available versions can be viewed at the "App Versions" tab for each
application in the console. To roll back to an earlier version, click on
the "Rollback to this version" button.

In the command-line client, to list all the versions for an app:

    stackato versions [_application_]
    
To select a particular version:

    stackato rollback [_application_] _version name_