#!/usr/bin/env bash

#------------------------------------------------------------------------------
# This script will setup everything need to run the spec tests for this repo.
#
# It is assumed that this repo will be cloned and setup on a working Stackato
# v3.4.2 (or higher) instance.
#
# The script can be run repeatedly. It will try to only do things that haven't
# been done yet.
#------------------------------------------------------------------------------
set -e

main() {
  chdir-to-ccng-repo
  sanity-check

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
  mkdir -p vendor/errors
  (
    set -x
    cd vendor/errors
    [ -e v2.yml ] ||
      ln -s ../../spec/errors-v2.yml v2.yml
  )
}

bundle-install() { bundle install; }

sanity-check() {
  local branch="$(git rev-parse --abbrev-ref HEAD)"
  # Make sure we are on the right branch for now:
  [ "$branch" == 300170-fix-specs ] ||
    die "You should have branch '300170-fix-specs' checked out"
}

# Make sure we start off in the right directory:
chdir-to-ccng-repo() {
  cd "$(cd "$(dirname $0)/.."; pwd)"
  [ -d .git ] &&
    [ -f "spec/$(basename $0)" ] ||
    die "Can't determine cc_ng location."
}

die() { echo "$@" >&2; exit 1; }

[ "$0" != "$BASH_SOURCE" ] || main "$@"

# vim: set lisp:
