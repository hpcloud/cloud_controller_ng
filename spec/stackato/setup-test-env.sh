#!/usr/bin/env bash

#------------------------------------------------------------------------------
# This script will setup everything need to run the spec tests for this repo.
#
# The script can be run repeatedly. It will try to only do things that haven't
# been done yet. Many things will just be verified and you will be instructed
# what to do if the verifications fail.
#------------------------------------------------------------------------------
set -e

main() {
  chdir-to-ccng-repo
  sanity-check
  setup-env

  clone-necessary-repos
  make-symlinks
  bundle-install
}

clone-necessary-repos() {
  local repo= repos=(
    ActiveState/kato
    ActiveState/steno-codec-text
    ActiveState/vcap-common
    cloudfoundry/cf-registrar
  )
  for repo in ${repos[@]}; do
    (
      set -x
      git clone git@github.com:$repo ../${repo#*/} || true
    )
  done
}

make-symlinks() {
  mkdir -p vendor/cache
  (
    set -x
    cd vendor/cache
    [ -e common ] || ln -s ../../../vcap-common common
    [ -e steno-codec-text ] || ln -s ../../../steno-codec-text
  )
}

bundle-install() {
  if [ -z "$(grep stackato-kato Gemfile | grep path)" ]; then
    patch -p1 < spec/stackato/Gemfile.patch
  fi
  bundle install
}

sanity-check() {
  type ruby &>/dev/null ||
    die "You don't have 'ruby' installed.
Install version '1.9.3p484'.
"
  [[ "$(ruby -v)" =~ \ 1\.9\.3p484\  ]] ||
    die "You need version ruby version '1.9.3p484'.
See spec/README.md for how to use rbenv to get this.
"
  type gem &>/dev/null ||
    die "You don't have 'gem' installed."
  type bundle &>/dev/null ||
    die "You don't have 'bundle' installed.
Try: 'gem install bundler'.
"
  type psql &>/dev/null ||
    die "You don't have 'psql' installed.
Try: 'sudo apt-get install postgresql-client-common postgresql-client-9.x'.

Note: postgresql-client-9.x could be 9.1 or 9.3 on Ubuntu 14.04
      You'll need to check which one.
"
  [ -e /usr/include/rrd.h ] ||
    die "Missing dep 'librrd-dev'.
Try: 'sudo apt-get install librrd-dev'
"
  [ -e /usr/include/mysql/ ] ||
    die "Missing dep 'libmysqlclient-dev'.
Try: 'sudo apt-get install libmysqlclient-dev'
"
  [ -e /usr/include/postgresql/libpq-fe.h ] ||
    die "Missing dep 'libpq-dev'.
Try: 'sudo apt-get install libpq-dev'
"
  [ -e /usr/include/sqlite3.h ] ||
    die "Missing dep 'libsqlite3-dev'.
Try: 'sudo apt-get install libsqlite3-dev'
"
  [ -e /etc/init.d/postgresql ] ||
    die "Missing dep 'postgresql-common'.
Try: 'sudo apt-get install postgresql postgresql-common postgresql-contrib'
"
}

setup-env() {
  export KATO_DEV=1
}

# Make sure we start off in the right directory:
chdir-to-ccng-repo() {
  cd "$(cd "$(dirname $0)/../.."; pwd)"
  [ -d .git ] &&
    [ -f "spec/stackato/$(basename $0)" ] ||
    die "Can't determine cloud_controller_ng location."
}

die() { echo "$@" >&2; exit 1; }

[ "$0" != "$BASH_SOURCE" ] || main "$@"

# vim: set lisp:
