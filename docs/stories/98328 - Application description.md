## Applications now support descriptions

There is now a per-application description field; the contents of this field can
be any free-form text.  The description is readable in the Stackato console,
both in the application listing as well as on the left side of the application
detail view.  In the latter case, URLs will be automatically linked as
appropriate; no markup is otherwise interpreted.

The description may be modified in the application detail view by clicking on
the gear icon in the About section.

The description can be set via the command line client via the `--description`
option of `stackato push`.  It may also be set in _stackato.yml_, at the top
level under the key `description`.