#!/usr/bin/env bash

set -e

# PGPASSFILE content:
# localhost:5432:cc_test:postgres:7o0j493ehp
export DB_TEST_USER=postgres
if type kato &>/dev/null; then
  export DB_TEST_PASSWORD="$(
    kato config get cloud_controller_ng |
      grep -E '^    password: [0-9a-z]{10}$' |
      sed 's/.* //'
  )"
else
  [ -n "$DB_TEST_PASSWORD" ] || die "
You need to:

  export DB_TEST_PASSWORD=<postgres-user-password>

If you don't know the password, do this:

  sudo -u postgres psql postgres
  \\password postgres

Enter a new password when prompted and exit with ctl-d.

"
  export DB_TEST_PASSWORD
fi
export LESS=-EiXm
export DB_TEST_DATABASE=cc_test
export DB_TEST_HOSTNAME=localhost
export DB_TEST_PORT=5432
export DB=postgres
export DB_CONNECTION="postgres://$DB_TEST_USER@$DB_TEST_HOSTNAME:$DB_TEST_PORT"
export DB_CONNECTION_STRING="postgres://$DB_TEST_USER@$DB_TEST_HOSTNAME:$DB_TEST_PORT/$DB_TEST_DATABASE"
export PGPASSWORD="$DB_TEST_PASSWORD"

export STACKATO_SKIP_WARN_REDUNDANCY=1

create_cc_test_done_file=/tmp/done_create_database_cc_test
if [ ! -e $create_cc_test_done_file ]; then
  echo 'create database cc_test;' | psql -U postgres -h localhost -p 5432
  touch $create_cc_test_done_file
fi

test_results="../test-results"

# bundle exec rake spec

if [ "$#" -eq 0 ]; then
  bundle exec rspec
  exit 0
elif [ "$1" == --all ]; then
  specs=($(find spec -type f | grep '_spec\.rb$'))
else
  specs=("$@")
fi

if [ ${#specs[@]} -gt 1 ]; then
  use_log=true
else
  use_log=false
fi

log() {
  echo "$1"
  if $use_log; then
    echo "$1" >> "$test_results/log"
  fi
}
log_after() {
  end_time="$(date +%s)"
  if $use_log; then
    log "  $1 - $(( end_time - start_time ))s - $2"
  fi
}
if $use_log; then
  rm -f "$test_results/log"
  begin_time="$(date +%s)"
  log "Start spec: $(date)"
  log ""
fi

# TODO:
# - Run in parallel
total_pass=0
total_fail=0
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

  log "* Running spec/$file"

  start_time="$(date +%s)"
  rc=0
  bundle exec rspec "$spec" &> "$temp_file" || rc=$?
  if [[ $rc -eq 0 ]]; then
    log_after PASS "$pass_file"
    mkdir -p "$pass_dir"
    mv "$temp_file" "$pass_file"
    ((++total_pass))
  else
    log_after FAIL "$fail_file"
    mkdir -p "$fail_dir"
    mv "$temp_file" "$fail_file"
    ((++total_fail))
  fi
done

if $use_log; then
  log ""
  log "Total spec: $((total_pass + total_fail))"
  log "Total pass: $total_pass"
  log "Total fail: $total_fail"
  end_time="$(date +%s)"
  dur=$(( end_time - begin_time ))
  hours=$(( dur / 3600 ))
  mins=$(( dur % 3600 / 60 ))
  secs=$(( dur % 3600 % 60 ))
  log "Total time: $hours hours, $mins mins, $secs secs"
fi

rm -fr "$test_results/temp"
