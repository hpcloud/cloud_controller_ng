#
# Makefile for stackato-cloud-controller-ng
#
# Used solely by packaging systems.
# Must support targets "all", "install", "uninstall".
#
# During the packaging install phase, the native packager will
# set either DESTDIR or prefix to the directory which serves as
# a root for collecting the package files.
#
# The resulting package installs in /home/stackato/stackato/code,
# is not intended to be relocatable.
#

NAME=stackato-cloud-controller-ng

INSTALLHOME=/home/stackato
INSTALLBASE=$(INSTALLHOME)/stackato
INSTALLROOT=$(INSTALLBASE)/code
DIRNAME=$(INSTALLROOT)/cloud_controller_ng

HOMEDIR=$(DESTDIR)$(prefix)$(INSTALLHOME)
BASEDIR=$(DESTDIR)$(prefix)$(INSTALLBASE)
INSTDIR=$(DESTDIR)$(prefix)$(DIRNAME)

PG_CONF_DIR=$(DESTDIR)/etc/postgresql/9.1/cloud_controller_ng

NPM_INSTALL_ARGS=--production

ifdef PKG_NPM_REGISTRY
    NPM_INSTALL_ARGS := $(addprefix --registry $(PKG_NPM_REGISTRY) , $(NPM_INSTALL_ARGS))
endif

#QQQ: Reinstate this one
# RSYNC_EXCLUDE=--exclude=.git* --exclude=/Makefile --exclude=/.stackato-pkg --exclude=/debian --exclude=/etc --exclude=/spec
RSYNC_EXCLUDE=--exclude=.git* --exclude=/Makefile --exclude=/.stackato-pkg --exclude=/debian --exclude=/etc

all:
	@ true

install:
	mkdir -p $(INSTDIR)
	rsync -ap . $(INSTDIR) $(RSYNC_EXCLUDE)
	if [ -d etc ] ; then rsync -ap etc $(BASEDIR) ; fi
	chmod a+x $(INSTDIR)/bin/*

	# Custom Postgresql Server Configuration
	mkdir -p $(PG_CONF_DIR) && \
	cp -fp $(INSTDIR)/config/postgresql/*.conf $(PG_CONF_DIR)/

	cd $(INSTDIR)/stackato/upload-server && npm install $(NPM_INSTALL_ARGS) .

	chown -R stackato.stackato $(HOMEDIR)

uninstall:
	rm -rf $(INSTDIR)
	rm -rf $(PG_CONF_DIR)

clean:
	@ true

sync: rsync restart

VM ?= $(VMNAME).local
rsync: vmname
	rsync -avzL ./ stackato@$(VM):/s/code/cloud_controller_ng/ $(RSYNC_EXCLUDE)

start stop restart: vmname
	ssh stackato@$(VM) sup $@ cloud_controller_ng

ssh: vmname
	ssh stackato@$(VM)

unfirstuser: vmname
	ssh stackato@$(VM) kato config set cluster license false --force

vmname:
ifndef VMNAME
	@echo "You need to set VMNAME. Something like this:"
	@echo
	@echo "export VMNAME=stackato-g4jx"
	@echo
	@exit 1
endif

dev-push:
	rsync -rtv --exclude .stackato-pkg --exclude .git \
		. stackato@${TARGET}:/s/code/cloud_controller_ng

# Test targets

# Runs tests assuming everything has been setup on the machine.
# Make sure to set DB_CONNECTION to the created database - i.e if running on a full VM:
# - export DB_CONNECTION="postgres://postgres:`kato config get stackato_rest db/database/password`@localhost:5432"
unit-test:
ifndef DB_CONNECTION
	DB_CONNECTION="postgres://postgres:postgres@localhost:5432" bundle exec rspec spec/unit
else
	bundle exec rspec spec/unit
endif

install-test-deps:
	sed -i.bak s/^BUNDLE_WITHOUT:/#BUNDLE_WITHOUT:/ .bundle/config
	bundle install

# xxx: Sep '14 - cc_ng tests currently rely on spec_helper.rb from kato/spec-common
install-spec-common:
	git clone 'http://git-mirrors.activestate.com/github.com/ActiveState/kato.git' /home/stackato/stackato/katotwo
	cp -R /home/stackato/stackato/katotwo/spec-common /home/stackato/stackato/kato
	rm -rf /home/stackato/stackato/katotwo

# Modified from http://docker.readthedocs.org/en/v0.7.3/examples/postgresql_service/
install-local-psql:
	sudo apt-get update
	wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
	echo "deb http://apt.postgresql.org/pub/repos/apt/ precise-pgdg main" | sudo tee --append /etc/apt/sources.list.d/pgdg.list
	sudo apt-get update
	-sudo apt-get -y install postgresql-9.3 postgresql-client-9.3 postgresql-contrib-9.3
	sudo su - postgres -c "psql -U postgres -d postgres -c \"alter user postgres with password 'postgres';\""
	sudo su - postgres -c "psql -U postgres -d postgres -c \"create database cc_test;\""


# Runs tests assuming a Sentinel-based install is on the machine and psql needs to be installed.
config-ci: install-spec-common install-test-deps install-local-psql
