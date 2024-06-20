# SPDX-FileCopyrightText: 2024 3mdeb <contact@3mdeb.com>
#
# SPDX-License-Identifier: Apache-2.0

SBINDIR ?= /usr/sbin
SYSCONFDIR ?= /etc

install:
	install -d $(DESTDIR)$(SBINDIR)

	install -m 0755 include/dts-environment.sh $(DESTDIR)$(SBINDIR)
	install -m 0755 include/dts-functions.sh $(DESTDIR)$(SBINDIR)
	install -m 0755 include/dts-subscription.sh $(DESTDIR)$(SBINDIR)

	install -m 0755 scripts/cloud_list $(DESTDIR)$(SBINDIR)
	install -m 0755 scripts/dasharo-deploy $(DESTDIR)$(SBINDIR)
	install -m 0755 scripts/dts $(DESTDIR)$(SBINDIR)
	install -m 0755 scripts/dts-boot $(DESTDIR)$(SBINDIR)
	install -m 0755 scripts/ec_transition $(DESTDIR)$(SBINDIR)

	install -m 0755 reports/dasharo-hcl-report $(DESTDIR)$(SBINDIR)
	install -m 0755 reports/touchpad-info $(DESTDIR)$(SBINDIR)

	install -d $(DESTDIR)$(SYSCONFDIR)/profile.d
	install -m 0755 dts-profile.sh $(DESTDIR)$(SYSCONFDIR)/profile.d
