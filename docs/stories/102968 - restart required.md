See http://bugs.activestate.com/show_bug.cgi?id=102968 and http://bugs.activestate.com/show_bug.cgi?id=103012

The cloud controller now tracks when apps have pending configuration changes that require a restart to take affect. Apps now have a restart_required (bool) field to record this.

Right now only two things will cause this to be set to true, 1) enabling/disabling sso and 2) changing environment variables.

The console shows this on apps list and app view and the cli has been updated to show an '(R)' beside apps in 's apps' e.g. 

+---------------+---+-----+-------------+-----------------------------------+----------+--------+
| Application   | # | Mem | Health      | URLS                              | Services | Drains |
+---------------+---+-----+-------------+-----------------------------------+----------+--------+
| aaaaenv-h6oa8 | 1 | 128 | RUNNING (-) | aaaaenv-h6oa8.stackato-qf2n.local |          |        |
| env-6wx2l     | 1 | 128 | RUNNING (R) | env-6wx2l.stackato-qf2n.local     |          |        |
| env-nkdmn     | 1 | 128 | RUNNING (-) | env-nkdmn.stackato-qf2n.local     |          |        |
| go-env-553g8  | 1 | 128 | RUNNING (-) | go-env-553g8.stackato-qf2n.local  |          |        |
| go-env-ph04t  | 1 | 128 | STOPPED (-) | go-env-ph04t.stackato-qf2n.local  |          |        |
| go-env-qwjvv  | 1 | 128 | STOPPED (-) | go-env-qwjvv.stackato-qf2n.local  |          |        |
| go-env-v06uq  | 1 | 128 | RUNNING (-) | go-env-v06uq.stackato-qf2n.local  |          |        |
+---------------+---+-----+-------------+-----------------------------------+----------+--------+