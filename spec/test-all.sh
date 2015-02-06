#!/usr/bin/env bash

# PGPASSFILE content:
# localhost:5432:cc_test:postgres:7o0j493ehp
export DB_TEST_USER=postgres
export DB_TEST_PASSWORD="$(
  kato config get cloud_controller_ng |
    grep -E '^    password: [0-9a-z]{10}$' |
    sed 's/.* //'
)"
export DB_TEST_DATABASE=cc_test
export DB_TEST_HOSTNAME=localhost
export DB_TEST_PORT=5432
export DB=postgres
export DB_CONNECTION="postgres://$DB_TEST_USER@$DB_TEST_HOSTNAME:$DB_TEST_PORT"
export DB_CONNECTION_STRING="postgres://$DB_TEST_USER@$DB_TEST_HOSTNAME:$DB_TEST_PORT/$DB_TEST_DATABASE"
export PGPASSWORD="$DB_TEST_PASSWORD"

bundle exec rake spec
