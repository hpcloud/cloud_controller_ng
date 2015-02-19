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

export STACKATO_SKIP_WARN_REDUNDANCY=1

test_results="../test-results"

# bundle exec rake spec

if [ "$#" -gt 0 ]; then
  specs=("$@")
else
  specs=($(find spec -type f | grep '_spec\.rb$'))
fi

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

  temp_dir="$test_results"/temp/"$dir"
  pass_dir="$test_results"/pass/"$dir"
  fail_dir="$test_results"/fail/"$dir"
  temp_file="$test_results"/temp/"$file"
  pass_file="$test_results"/pass/"$file"
  fail_file="$test_results"/fail/"$file"

  mkdir -p "$temp_dir"

  printf "* Running spec/$file - "

  rc=0
  bundle exec rspec "$spec" &> "$temp_file" || rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "PASS ($pass_file)"
    mkdir -p "$pass_dir"
    mv "$temp_file" "$pass_file"
  else
    echo "FAIL ($fail_file)"
    mkdir -p "$fail_dir"
    mv "$temp_file" "$fail_file"
  fi
done

rm -fr "$test_results/temp"
