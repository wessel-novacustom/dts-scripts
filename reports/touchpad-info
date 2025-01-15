#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2024 3mdeb <contact@3mdeb.com>
#
# SPDX-License-Identifier: Apache-2.0

# A script to get information on the touchpad devices. Currently supports only
# Clevo devices.

# shellcheck source=../include/hal/dts-hal.sh
source $DTS_HAL

if ! $DMESG i2c_hid_detect_mock | grep hid-multitouch | grep "I2C HID" > /dev/null; then
  echo "No I2C touchpads detected. Exiting"
  exit 2
fi

devname=$($DMESG i2c_hid_detect_mock | grep hid-multitouch | awk 'NF>1{print $NF}')
hid=$($FSREAD_TOOL cat "/sys/bus/i2c/devices/$devname/firmware_node/hid")
path=$($FSREAD_TOOL cat "/sys/bus/i2c/devices/$devname/firmware_node/path")

ACPI_CALL_PATH="/proc/acpi/call"

if [ ! -f "$ACPI_CALL_PATH" ]; then
   echo "File ${ACPI_CALL_PATH} doesn\'t exist..."
   return 3
fi

echo "$path._DSM bF7F6DF3C67425545AD05B30A3D8938DE 1 1" > ${ACPI_CALL_PATH}
descriptor_offset=$(tr -d '\0' < ${ACPI_CALL_PATH} | cut -d 'c' -f 1)

i2c_row=$(i2cdetect -y -r 0 | grep UU)
i2c_col=0
for x in $i2c_row
do
  if [ "$x" = 'UU' ]; then
  	break;
  fi
  i2c_col=$(($i2c_col + 1))
done

i2c_addr=$(echo "$i2c_row" | cut -d ":" -f 1)
i2c_col=$(printf '%s\n' $(($i2c_col - 1)))
i2c_addr=$(printf '%s\n' $(($i2c_addr + $i2c_col)))

echo "Found touchpad at: $path:"
echo
echo "HID:                $hid"
echo "I2C address:        0x$i2c_addr"
echo "Descriptor address: $descriptor_offset"
echo
