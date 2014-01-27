# Domains API changes

## Api

* NEW /v2/shared_domains - any authenticated user can read, only admins can
modify. Can be mapped to many orgs.

* NEW /v2/private_domains - any org user can read, only org managers can modify.
Can be mapped to single org.

* NEW /v2/organizations/:guid/private_domains - same as /v2/private_domains

* CHANGED /v2/organizations/:guid/domains - orgs automatically inherit shared
domains and they cannot be unmapped, so this lists private + shared.

* CHANGED /v2/spaces/:space_guid/domains - spaces now inherit their orgs domains
(private + shared) and they cannot be unmapped

* CHANGED domain.wildcard property no longer exists

## Overview

The domains api has changed. The behaviour of having shared domains (available to all orgs) and private domains (owned by a single org) still exists but the way in which domains are attached to orgs has changed.

Previously domains had to be 'mapped' to an org, and then to a space. Now orgs automatically inherit shared domains, and spaces inherit the domains from their org (so spaces end up automatically inheriting all shared domains as well as all private domains from their org).

Domains also no longer have the 'wildcard' property. Domains are inherently treated as wildcard domains now. So if you create a domain called ```foobar.com``` you can create a route with an empty host field and browse to ```foobar.com``` to access your app. Or you can create a route with a populated host field e.g. ```baaaah.foobar.com```.

Basically the model has been simplified and is less flexible as you can no longer choose to map a domain only to a single space, or exclude domains from a given space. You also can't force domains to only be accessable as a top level domain as they're now all treated as wildcard domains.
