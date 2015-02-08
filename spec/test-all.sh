#!/usr/bin/env bash

set -e

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

# bundle exec rake spec

specs=($(find spec -type f | grep '_spec\.rb$'))

# Add a timer
# Log results
# Run in parallel
# Add support for a list of test patterns
for spec in "${specs[@]}"; do
  # XXX This test hangs currently:
  [ "$spec" != spec/unit/lib/background_job_environment_spec.rb ] ||
    continue

  file="${spec#spec/}"
  dir=$(dirname $file)
  mkdir -p pass/$dir
  echo "* Running spec/$file"

  rc=0
  bundle exec rspec $spec &> pass/$file || rc=$?
  if [[ $rc -ne 0 ]]; then
    mkdir -p fail/$dir
    mv pass/$file fail/$file
    rmdir --ignore-fail-on-non-empty pass/$dir
  fi
done
