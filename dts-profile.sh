#!/bin/sh

# SPDX-FileCopyrightText: 2024 3mdeb <contact@3mdeb.com>
#
# SPDX-License-Identifier: Apache-2.0

SBIN_DIR="/usr/sbin"
export DTS_FUNCS="$SBIN_DIR/dts-functions.sh"
export DTS_ENV="$SBIN_DIR/dts-environment.sh"
export DTS_SUBS="$SBIN_DIR/dts-subscription.sh"
