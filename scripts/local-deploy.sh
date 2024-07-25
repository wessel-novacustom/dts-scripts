#!/usr/bin/env bash

# This scripts deplos DTS scripts into target machine, for local development

IP_ADDR="$1"
PORT=${PORT:-22}

scp -P ${PORT} \
  -O \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  include/* \
  reports/* \
  scripts/* \
  tests/* \
  dts-profile.sh \
  root@${IP_ADDR}:/usr/sbin
