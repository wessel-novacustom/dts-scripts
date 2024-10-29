#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2024 3mdeb <contact@3mdeb.com>
#
# SPDX-License-Identifier: Apache-2.0

# shellcheck disable=SC2034
# shellcheck source=../include/hal/dts-hal.sh
source $DTS_HAL
# shellcheck source=../include/dts-functions.sh
source $DTS_FUNCS

# Text colors:
NORMAL='\033[0m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;36m'

# DPP variables:
DPP_SERVER_ADDRESS="https://dl.dasharo.com"
DPP_SERVER_USER_ALIAS="premium"
DPP_PACKAGE_MANAGER_DIR="/var/dasharo-package-manager"
DPP_AVAIL_PACKAGES_LIST="$DPP_PACKAGE_MANAGER_DIR/packages-list.json"
DPP_PACKAGES_SCRIPTS_PATH="$DPP_PACKAGE_MANAGER_DIR/packages-scripts"
DPP_SUBMENU_JSON="$DPP_PACKAGES_SCRIPTS_PATH/submenu.json"
DPP_CREDENTIAL_FILE="/etc/cloud-pass"
FW_STORE_URL="${FW_STORE_URL_DEV:-https://dl.3mdeb.com/open-source-firmware/Dasharo}"
FW_STORE_URL_DPP="https://cloud.3mdeb.com/public.php/webdav"
CLOUD_REQUEST="X-Requested-With: XMLHttpRequest"
BASE_CLOUDSEND_LOGS_URL="39d4biH4SkXD8Zm"
BASE_CLOUDSEND_PASSWORD="1{\[\k6G"
DEPLOY_REPORT="false"

# DTS menu options:
HCL_REPORT_OPT="1"
DASHARO_FIRM_OPT="2"
REST_FIRM_OPT="3"
DPP_KEYS_OPT="4"
DPP_SUBMENU_OPT="5"
BACK_TO_MAIN_MENU_UP="Q"
BACK_TO_MAIN_MENU_DOWN="$(echo $BACK_TO_MAIN_MENU_UP | awk '{print tolower($0)}')"
REBOOT_OPT_UP="R"
REBOOT_OPT_LOW="$(echo $REBOOT_OPT_UP | awk '{print tolower($0)}')"
POWEROFF_OPT_UP="P"
POWEROFF_OPT_LOW="$(echo $POWEROFF_OPT_UP | awk '{print tolower($0)}')"
SHELL_OPT_UP="S"
SHELL_OPT_LOW="$(echo $SHELL_OPT_UP | awk '{print tolower($0)}')"
SSH_OPT_UP="K"
SSH_OPT_LOW="$(echo $SSH_OPT_UP | awk '{print tolower($0)}')"
SEND_LOGS_OPT="L"
SEND_LOGS_OPT_LOW="$(echo $SEND_LOGS_OPT | awk '{print tolower($0)}')"
VERBOSE_OPT="V"
VERBOSE_OPT_LOW="$(echo $VERBOSE_OPT | awk '{print tolower($0)}')"

# Hardware variables:
SYSTEM_VENDOR="$($DMIDECODE dump_var_mock -s system-manufacturer)"
SYSTEM_MODEL="$($DMIDECODE dump_var_mock -s system-product-name)"
BOARD_MODEL="$($DMIDECODE dump_var_mock -s baseboard-product-name)"
CPU_VERSION="$($DMIDECODE dump_var_mock -s processor-version)"

# Firmware variables
BIOS_VENDOR="$($DMIDECODE dump_var_mock -s bios-vendor)"
BIOS_VERSION="$($DMIDECODE dump_var_mock -s bios-version)"
DASHARO_VERSION="$(echo $BIOS_VERSION | cut -d ' ' -f 3 | tr -d 'v')"
DASHARO_FLAVOR="$(echo $BIOS_VERSION | cut -d ' ' -f 1,2)"

# Paths to temporary files, created while deploying or updating Dasharo
# firmware, are used globally for both: updating via binaries and via UEFI
# Capsule Update.
BIOS_UPDATE_FILE="/tmp/biosupdate"
BIOS_DUMP_FILE="/tmp/bios.bin"
EC_UPDATE_FILE="/tmp/ecupdate"
BIOS_HASH_FILE="/tmp/bioshash.sha256"
EC_HASH_FILE="/tmp/echash.sha256"
BIOS_SIGN_FILE="/tmp/biossignature.sig"
EC_SIGN_FILE="/tmp/ecsignature.sig"
BIOS_UPDATE_CONFIG_FILE="/tmp/biosupdate_config"
RESIGNED_BIOS_UPDATE_FILE="/tmp/biosupdate_resigned.rom"
SYSTEM_UUID_FILE="/tmp/system_uuid.txt"
SERIAL_NUMBER_FILE="/tmp/serial_number.txt"

# dasharo-deploy backup cmd related variables, do we still use and need this as
# backup is placed in HCL?
ROOT_DIR="/"
FW_BACKUP_NAME="fw_backup"
FW_BACKUP_DIR="${ROOT_DIR}${FW_BACKUP_NAME}"
FW_BACKUP_TAR="${FW_BACKUP_DIR}.tar.gz"
FW_BACKUP_TAR="$(echo "$FW_BACKUP_TAR" | sed 's/\ /_/g')"

# Paths to system files
ERR_LOG_FILE="/var/local/dts-err.log"
FLASHROM_LOG_FILE="/var/local/flashrom.log"
FLASH_INFO_FILE="/tmp/flash_info"
OS_VERSION_FILE="/etc/os-release"
KEYS_DIR="/tmp/devkeys"

# Paths to system commands:
CMD_SHELL="bash"

# Paths to DTS commands:
CMD_DASHARO_HCL_REPORT="/usr/sbin/dasharo-hcl-report"
CMD_NCMENU="/usr/sbin/novacustom_menu"
CMD_DASHARO_DEPLOY="/usr/sbin/dasharo-deploy"
CMD_CLOUD_LIST="/usr/sbin/cloud_list"
CMD_EC_TRANSITION="/usr/sbin/ec_transition"

# Configuration variables declaration and default values (see dts-functions.sh/
# board_config function for more inf.):
# Versions and names:
declare DASHARO_REL_NAME
declare DASHARO_REL_VER
declare DASHARO_REL_VER_DPP
declare DASHARO_REL_VER_DPP_CAP
declare HEADS_REL_VER_DPP
declare DASHARO_REL_VER_DPP_SEABIOS
declare COMPATIBLE_EC_FW_VERSION
# and for capsules:
declare DASHARO_REL_VER_CAP
declare DASHARO_REL_VER_DPP_CAP
# Links to files:
declare BIOS_LINK_COMM
declare BIOS_HASH_LINK_COMM
declare BIOS_SIGN_LINK_COMM
declare BIOS_LINK_DPP
declare BIOS_HASH_LINK_DPP
declare BIOS_SIGN_LINK_DPP
declare BIOS_LINK_DPP_SEABIOS
declare BIOS_HASH_LINK_DPP_SEABIOS
declare BIOS_SIGN_LINK_DPP_SEABIOS
declare EC_LINK_COMM
declare EC_HASH_LINK_COMM
declare EC_SIGN_LINK_COMM
declare EC_LINK_DPP
declare EC_HASH_LINK_DPP
declare EC_SIGN_LINK_DPP
declare HEADS_LINK_DPP
declare HEADS_HASH_LINK_DPP
declare HEADS_SIGN_LINK_DPP
# and for capsules:
declare BIOS_LINK_COMM_CAP
declare BIOS_HASH_LINK_COMM_CAP
declare BIOS_SIGN_LINK_COMM_CAP
declare BIOS_LINK_DPP_CAP
declare BIOS_HASH_LINK_DPP_CAP
declare BIOS_SIGN_LINK_DPP_CAP
declare EC_LINK_COMM_CAP
declare EC_HASH_LINK_COMM_CAP
declare EC_SIGN_LINK_COMM_CAP
# Configs, are used in dasharo-deploy script:
CAN_INSTALL_BIOS="false"
HAVE_HEADS_FW="false"
HAVE_EC="false"
NEED_EC_RESET="false"
NEED_SMBIOS_MIGRATION="false"
NEED_SMMSTORE_MIGRATION="false"
NEED_BOOTSPLASH_MIGRATION="false"
NEED_BLOB_TRANSMISSION="false"
NEED_ROMHOLE_MIGRATION="false"
# Default flashrom parameters, may differ depending on a platform:
PROGRAMMER_BIOS="internal"
PROGRAMMER_EC="ite_ec:boardmismatch=force,romsize=128K,autoload=disable"
declare FLASHROM_ADD_OPT_UPDATE_OVERRIDE
declare HEADS_SWITCH_FLASHROM_OPT_OVERRIDE
# Platform-specific:
declare PLATFORM_SIGN_KEY

# Other variables:
# Default values for flash chip related information:
declare FLASH_CHIP_SELECT
declare FLASH_CHIP_SIZE
# Default UEFI Capsule Update device:
CAP_UPD_DEVICE="/dev/efi_capsule_loader"
# Variables defining Dasharo specific entries in DMI tables, used to check if
# Dasharo FW is already installed:
DASHARO_VENDOR="3mdeb"
DASHARO_NAME="Dasharo"
# Most the time one flash chipset will be detected, for other cases (like for
# ASUS KGPE-D16) we will test the following list in check_flash_chip function:
FLASH_CHIP_LIST="W25Q64BV/W25Q64CV/W25Q64FV W25Q64JV-.Q W25Q128.V..M"

BASE_DTS_LOGS_URL="xjBCYbzFdyq3WLt"
DTS_LOGS_PASSWORD="/w\J&<y1"

# set custom localization for PGP keys
if [ -d /home/root/.dasharo-gnupg ]; then
    GNUPGHOME=/home/root/.dasharo-gnupg

    export GNUPGHOME
fi
