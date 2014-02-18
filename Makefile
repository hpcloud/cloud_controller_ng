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

RSYNC_EXCLUDE=--exclude=/.git* --exclude=/Makefile --exclude=/.stackato-pkg --exclude=/debian --exclude=/etc --exclude=/spec

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

VM=$(VMNAME).local
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

# eg: make dev-push VM=y9ba
dev-push:
	rsync -rtv --exclude .stackato-pkg --exclude .git \
		. stackato@stackato-${VM}.local:/s/code/cloud_controller_ng
