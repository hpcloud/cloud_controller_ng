#
# Makefile for stackato-vcap-cloud-controller-ng
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

NAME=stackato-vcap-cloud-controller-ng

INSTALLHOME=/home/stackato
INSTALLBASE=$(INSTALLHOME)/stackato
INSTALLROOT=$(INSTALLBASE)/code
DIRNAME=$(INSTALLROOT)/cloud_controller_ng

HOMEDIR=$(DESTDIR)$(prefix)$(INSTALLHOME)
BASEDIR=$(DESTDIR)$(prefix)$(INSTALLBASE)
INSTDIR=$(DESTDIR)$(prefix)$(DIRNAME)

KATO_CONF_DIR = $(HOMEDIR)/etc/kato
PG_CONF_DIR = $(DESTDIR)/etc/postgresql/9.1/cloud_controller_ng
SUPERVISORD_CONF_DIR = $(HOMEDIR)/etc/supervisord.conf.d

RSYNC_EXCLUDE=--exclude=/.git* --exclude=/Makefile --exclude=/.stackato-pkg --exclude=/debian --exclude=/etc

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
	
	# Supervisord config
	mkdir -p $(SUPERVISORD_CONF_DIR) \
	cp -fp config/supervisord/* $(SUPERVISORD_CONF_DIR)/
	
	# Kato config
	mkdir -p $(KATO_CONF_DIR) \
	cp -rfp config/kato/* $(KATO_CONF_DIR)/
	
	chown -R stackato.stackato $(HOMEDIR)

uninstall:
	rm -rf $(INSTDIR)
	rm -rf $(PG_CONF_DIR)

clean:
	@ true
