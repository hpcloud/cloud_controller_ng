#!/bin/bash -e

. /scripts/common.sh

echo "ALTER ROLE postgres ENCRYPTED PASSWORD '$1';" | psql -h /tmp
echo '\connect' | PGPASSWORD=$1 psql --username=postgres --no-password -h localhost"
