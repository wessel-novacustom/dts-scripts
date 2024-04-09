# Makefile for installing/uninstalling scripts.

DTS_PROFILE = dts-profile.sh
DTS_INCLUDE = dts-environment.sh dts-functions.sh
DTS_SCRIPTS = cloud_list dasharo-deploy dts dts-boot ec_transition

DTS_PROFILE_DEST = $(DTS_PROFILE:%=$(DESTDIR)/$(SYSCONFDIR)/%)
DTS_INCLUDE_DEST = $(DTS_INCLUDE:%=$(DESTDIR)/%)
DTS_SCRIPTS_DEST = $(DTS_SCRIPTS:%=$(DESTDIR)/%)

install: $(DTS_PROFILE_DEST) $(DTS_INCLUDE_DEST) $(DTS_SCRIPTS_DEST)

$(DTS_PROFILE_DEST):
	install -D -m 0755 $$(find ./ -type f -name $(notdir $@)) $@

$(DTS_INCLUDE_DEST):
	install -D -m 0655 $$(find ./ -type f -name $(notdir $@)) $@

$(DTS_SCRIPTS_DEST):
	install -D -m 0755 $$(find ./ -type f -name $(notdir $@)) $@
