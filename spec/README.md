## Instructions for running spec tests

The setup and running of these tests has been automated as follows:

Run these commands (from the top level directory of this repo):

    ./spec/stackato/setup-test-env.sh
    ./spec/stackato/run-spec-tests.sh

Notes:

* These scripts check to make sure that everything is setup properly.
* This has only been tested on Ubuntu Linux 14.04.
* These tests can be run on any Ubuntu machine, not just a Stackato instance.

## Prequisite Setup

Although the scripts check for everything and tell you what to do, you'll do
best to set these prereqs up first. From a brand new Ubuntu 14.04 instance:


    sudo apt-get update
    sudo apt-get install \
        git build-essential zlib1g-dev \
        libssl-dev libgnutls-openssl27
    sudo apt-get install \
        postgresql-client-common postgresql-client-9.1 \
        librrd-dev libmysqlclient-dev libpq-dev libsqlite3-dev \
        postgresql postgresql-common postgresql-contrib

    git clone https://github.com/ActiveState/cloud_controller_ng
    cd cloud_controller_ng
    git checkout 300170-standalone

    git clone https://github.com/sstephenson/rbenv.git ~/.rbenv
    git clone https://github.com/sstephenson/ruby-build.git ~/.rbenv/plugins/ruby-build
    export PATH="$HOME/.rbenv/bin:$PATH"
    eval "$(rbenv init -)"
    rbenv install 1.9.3-p484
    rbenv global 1.9.3-p484
    gem install bundle

    ./spec/stackato/setup-test-env.sh
    ./spec/stackato/run-spec-tests.sh

## Running Tests Individually

To run the tests individually for dev:

    ./spec/stackato/run-spec-tests.sh --all

or to run specific tests:

    ./spec/stackato/run-spec-tests.sh <spec/file/path>...

This will put results into ../test-results/ for easier analysis.
