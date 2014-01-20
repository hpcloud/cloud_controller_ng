## GZIP compression now enabled on API responses

GZIP is now used to compress responses from the API. This significantly reduces the size of the API response at the cost of a minor performance hit on the server. GZIP is a common compression format for the web and should be handled transparently by web browsers and standard HTTP stacks in all modern  languages (Java, C#, Node.js, Ruby etc.)

## Pretty printing API responses now disabled by default

API responses are no longer pretty printed by default. They are stripped of all whitespace which makes them harder for a human to read but faster for the server to generate and send to API clients (like the cli or web console).

A new query parameter ````?pretty```` can be specified on each API call to turn on pretty printing for a specific request. Valid values are '1' (on) or '0' (off) - which is the same as not specifying it at all.

GET ```/v2/apps/c647c0e3-0b71-4279-95f5-5efbdce35219```

```
{"metadata":{"guid":"c647c0e3-0b71-4279-95f5-5efbdce35219","url":"/v2/apps/c647c0e3-0b71-4279-95f5-5efbdce35219","created_at":"2014-01-19T13:26:15-08:00","updated_at":"2014-01-19T13:26:24-08:00"},"entity":{"guid":"c647c0e3-0b71-4279-95f5-5efbdce35219","name":"anv-bs8px","production":false,"space_guid":"14287f87-6ad2-4b04-b6c6-f9e7a286d395","stack_guid":"292c5e02-0ee1-43f5-bfd8-40f59841405a","buildpack":null,"detected_buildpack":null,"environment_json":{},"memory":128,"instances":1,"disk_quota":2048,"state":"STOPPED","version":"a05ce104-144c-4e39-bc78-b2a0cc9971af","command":null,"console":false,"debug":null,"staging_task_id":null,"space_url":"/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395","stack_url":"/v2/stacks/292c5e02-0ee1-43f5-bfd8-40f59841405a","service_bindings_url":"/v2/apps/c647c0e3-0b71-4279-95f5-5efbdce35219/service_bindings","routes_url":"/v2/apps/c647c0e3-0b71-4279-95f5-5efbdce35219/routes","events_url":"/v2/apps/c647c0e3-0b71-4279-95f5-5efbdce35219/events"}}
```

GET ```/v2/apps/c647c0e3-0b71-4279-95f5-5efbdce35219?pretty=1```

```
{
  "metadata": {
    "guid": "c647c0e3-0b71-4279-95f5-5efbdce35219",
    "url": "/v2/apps/c647c0e3-0b71-4279-95f5-5efbdce35219",
    "created_at": "2014-01-19T13:26:15-08:00",
    "updated_at": "2014-01-19T13:26:24-08:00"
  },
  "entity": {
    "guid": "c647c0e3-0b71-4279-95f5-5efbdce35219",
    "name": "anv-bs8px",
    "production": false,
    "space_guid": "14287f87-6ad2-4b04-b6c6-f9e7a286d395",
    "stack_guid": "292c5e02-0ee1-43f5-bfd8-40f59841405a",
    "buildpack": null,
    "detected_buildpack": null,
    "environment_json": {

    },
    "memory": 128,
    "instances": 1,
    "disk_quota": 2048,
    "state": "STOPPED",
    "version": "a05ce104-144c-4e39-bc78-b2a0cc9971af",
    "command": null,
    "console": false,
    "debug": null,
    "staging_task_id": null,
    "space_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395",
    "stack_url": "/v2/stacks/292c5e02-0ee1-43f5-bfd8-40f59841405a",
    "service_bindings_url": "/v2/apps/c647c0e3-0b71-4279-95f5-5efbdce35219/service_bindings",
    "routes_url": "/v2/apps/c647c0e3-0b71-4279-95f5-5efbdce35219/routes",
    "events_url": "/v2/apps/c647c0e3-0b71-4279-95f5-5efbdce35219/events"
  }
}
```

## API responses can now be reordered

There is a new ```?order-by``` query parameter that allows API responses to be ordered by a specific field. Specifying the name of the field will cause the response to be ordered in ascending order by the content of the field.

e.g. GET ```/v2/apps?order-by=name``` will return a list of applications ordered by name.

If the ```?order-by``` query isn't specified, or an invalid field is specified, the response will have a default ordering applied.

## Improved data structure when using ?inline-relations-depth query parameter

There is a new, more efficient, data structure that the API can return when listing resources with the ```?inline-relations-depth``` query parameter.

The new format is optional and can be requested by specifying an additional query parameter ```?orphan-relations```. Valid values are '1' (on) or '0' (off) - which is the same as not specifying it at all.

Instead of inlining related objects within their parent object the new data format will add related objects to a 'relations' object in the API response, keyed by guid. This removes the duplication of related objects that would often occur with the old data format and can significantly reduce the size of the response.

It is recomended to use this new format when possible. It is relatively easy to for clients to convert it in to the old format to remain compatible with existing code.

For ```1:1``` relations the related object can be found by first looking up its guid from the parent object, then using that guid to retrieve the relation from the relations object.

e.g. An application has a ```space_guid``` property, if ```inline-relations-depth=1``` is specified then the space will be included in the response. If using the original format then the application will have a ```space``` property that contains the space, however if ```orphan-relations=1``` is also specified then instead of the application having the space attached to it directly it will instead be in the relations object.

For ```1:M``` relations the related objects are put in to the new relations object and the collection on the parent object where they would have previously been embedded now contains a list of guids that can be used to look the objects up.

e.g. An application has many routes, if ```inline-relations-depth=1``` is specified then the routes will be included in the response. If using the original format then the application will have a ```routes``` property that contains an array of routes, however if ```orphan-relations=1``` is also specified then instead of the application having the routes attached to it directly it will instead have an array of route guids and the routes will be in the relations object.

GET ```/v2/apps?pretty=1&inline-relations-depth=1```

```
{
  "total_results": 1,
  "total_pages": 1,
  "prev_url": null,
  "next_url": null,
  "resources": [
    {
      "metadata": {
        "guid": "9cb59c71-f2d0-4348-9945-62e21d9a0c6a",
        "url": "/v2/apps/9cb59c71-f2d0-4348-9945-62e21d9a0c6a",
        "created_at": "2014-01-19T13:22:02-08:00",
        "updated_at": "2014-01-19T13:22:50-08:00"
      },
      "entity": {
        "guid": "9cb59c71-f2d0-4348-9945-62e21d9a0c6a",
        "name": "env-xw008",
        "production": false,
        "space_guid": "14287f87-6ad2-4b04-b6c6-f9e7a286d395",
        "stack_guid": "292c5e02-0ee1-43f5-bfd8-40f59841405a",
        "buildpack": null,
        "detected_buildpack": "Node.js",
        "environment_json": {

        },
        "memory": 128,
        "instances": 1,
        "disk_quota": 2048,
        "state": "STARTED",
        "version": "d0afa65d-900c-4477-8cc6-9b4ed7f94c3d",
        "command": null,
        "console": true,
        "debug": null,
        "staging_task_id": "c17f2edc078a8e304cac1f15a733927a",
        "space_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395",
        "space": {
          "metadata": {
            "guid": "14287f87-6ad2-4b04-b6c6-f9e7a286d395",
            "url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395",
            "created_at": "2014-01-19T13:21:28-08:00",
            "updated_at": null
          },
          "entity": {
            "name": "Development",
            "organization_guid": "d7978328-3048-4d71-8d6f-48a0f0d46cae",
            "organization_url": "/v2/organizations/d7978328-3048-4d71-8d6f-48a0f0d46cae",
            "developers_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/developers",
            "managers_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/managers",
            "auditors_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/auditors",
            "apps_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/apps",
            "domains_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/domains",
            "service_instances_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/service_instances",
            "app_events_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/app_events",
            "events_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/events"
          }
        },
        "stack_url": "/v2/stacks/292c5e02-0ee1-43f5-bfd8-40f59841405a",
        "stack": {
          "metadata": {
            "guid": "292c5e02-0ee1-43f5-bfd8-40f59841405a",
            "url": "/v2/stacks/292c5e02-0ee1-43f5-bfd8-40f59841405a",
            "created_at": "2014-01-19T04:37:18-08:00",
            "updated_at": null
          },
          "entity": {
            "name": "lucid64",
            "description": "Ubuntu 10.04 on x86-64"
          }
        },
        "service_bindings_url": "/v2/apps/9cb59c71-f2d0-4348-9945-62e21d9a0c6a/service_bindings",
        "service_bindings": [

        ],
        "routes_url": "/v2/apps/9cb59c71-f2d0-4348-9945-62e21d9a0c6a/routes",
        "routes": [
          {
            "metadata": {
              "guid": "4711ba29-23d7-4819-9dc0-c86683649f38",
              "url": "/v2/routes/4711ba29-23d7-4819-9dc0-c86683649f38",
              "created_at": "2014-01-19T13:22:11-08:00",
              "updated_at": null
            },
            "entity": {
              "host": "env-xw008",
              "domain_guid": "bf19c72b-1c73-479f-9ff4-1b1d7db857dc",
              "space_guid": "14287f87-6ad2-4b04-b6c6-f9e7a286d395",
              "domain_url": "/v2/domains/bf19c72b-1c73-479f-9ff4-1b1d7db857dc",
              "space_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395",
              "apps_url": "/v2/routes/4711ba29-23d7-4819-9dc0-c86683649f38/apps"
            }
          }
        ],
        "events_url": "/v2/apps/9cb59c71-f2d0-4348-9945-62e21d9a0c6a/events",
        "events": [

        ]
      }
    }
  ]
}
```

GET ```/v2/apps?pretty=1&inline-relations-depth=1&orphan-relations=1```

```
{
  "total_results": 1,
  "total_pages": 1,
  "prev_url": null,
  "next_url": null,
  "resources": [
    {
      "metadata": {
        "guid": "9cb59c71-f2d0-4348-9945-62e21d9a0c6a",
        "url": "/v2/apps/9cb59c71-f2d0-4348-9945-62e21d9a0c6a",
        "created_at": "2014-01-19T13:22:02-08:00",
        "updated_at": "2014-01-19T13:22:50-08:00"
      },
      "entity": {
        "guid": "9cb59c71-f2d0-4348-9945-62e21d9a0c6a",
        "name": "env-xw008",
        "production": false,
        "space_guid": "14287f87-6ad2-4b04-b6c6-f9e7a286d395",
        "stack_guid": "292c5e02-0ee1-43f5-bfd8-40f59841405a",
        "buildpack": null,
        "detected_buildpack": "Node.js",
        "environment_json": {

        },
        "memory": 128,
        "instances": 1,
        "disk_quota": 2048,
        "state": "STARTED",
        "version": "d0afa65d-900c-4477-8cc6-9b4ed7f94c3d",
        "command": null,
        "console": true,
        "debug": null,
        "staging_task_id": "c17f2edc078a8e304cac1f15a733927a",
        "space_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395",
        "stack_url": "/v2/stacks/292c5e02-0ee1-43f5-bfd8-40f59841405a",
        "service_bindings_url": "/v2/apps/9cb59c71-f2d0-4348-9945-62e21d9a0c6a/service_bindings",
        "service_bindings": [

        ],
        "routes_url": "/v2/apps/9cb59c71-f2d0-4348-9945-62e21d9a0c6a/routes",
        "routes": [
          "4711ba29-23d7-4819-9dc0-c86683649f38"
        ],
        "events_url": "/v2/apps/9cb59c71-f2d0-4348-9945-62e21d9a0c6a/events",
        "events": [

        ]
      }
    }
  ],
  "relations": {
    "14287f87-6ad2-4b04-b6c6-f9e7a286d395": {
      "metadata": {
        "guid": "14287f87-6ad2-4b04-b6c6-f9e7a286d395",
        "url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395",
        "created_at": "2014-01-19T13:21:28-08:00",
        "updated_at": null
      },
      "entity": {
        "name": "Development",
        "organization_guid": "d7978328-3048-4d71-8d6f-48a0f0d46cae",
        "organization_url": "/v2/organizations/d7978328-3048-4d71-8d6f-48a0f0d46cae",
        "developers_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/developers",
        "managers_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/managers",
        "auditors_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/auditors",
        "apps_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/apps",
        "domains_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/domains",
        "service_instances_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/service_instances",
        "app_events_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/app_events",
        "events_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395/events"
      }
    },
    "292c5e02-0ee1-43f5-bfd8-40f59841405a": {
      "metadata": {
        "guid": "292c5e02-0ee1-43f5-bfd8-40f59841405a",
        "url": "/v2/stacks/292c5e02-0ee1-43f5-bfd8-40f59841405a",
        "created_at": "2014-01-19T04:37:18-08:00",
        "updated_at": null
      },
      "entity": {
        "name": "lucid64",
        "description": "Ubuntu 10.04 on x86-64"
      }
    },
    "4711ba29-23d7-4819-9dc0-c86683649f38": {
      "metadata": {
        "guid": "4711ba29-23d7-4819-9dc0-c86683649f38",
        "url": "/v2/routes/4711ba29-23d7-4819-9dc0-c86683649f38",
        "created_at": "2014-01-19T13:22:11-08:00",
        "updated_at": null
      },
      "entity": {
        "host": "env-xw008",
        "domain_guid": "bf19c72b-1c73-479f-9ff4-1b1d7db857dc",
        "space_guid": "14287f87-6ad2-4b04-b6c6-f9e7a286d395",
        "domain_url": "/v2/domains/bf19c72b-1c73-479f-9ff4-1b1d7db857dc",
        "space_url": "/v2/spaces/14287f87-6ad2-4b04-b6c6-f9e7a286d395",
        "apps_url": "/v2/routes/4711ba29-23d7-4819-9dc0-c86683649f38/apps"
      }
    }
  }
}
```