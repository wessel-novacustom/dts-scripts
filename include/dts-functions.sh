#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2024 3mdeb <contact@3mdeb.com>
#
# SPDX-License-Identifier: Apache-2.0

# shellcheck disable=SC2034

### Color functions:
function echo_green() {
  echo -e "$GREEN""$1""$NORMAL"
}

function echo_red() {
  echo -e "$RED""$1""$NORMAL"
}

function echo_yellow() {
  echo -e "$YELLOW""$1""$NORMAL"
}

print_warning() {
  echo_yellow "$1"
}

print_error() {
  echo_red "$1"
}

print_ok() {
  echo_green "$1"
}

check_if_dasharo() {
  if [[ $BIOS_VENDOR == *$DASHARO_VENDOR* && $BIOS_VERSION == *$DASHARO_NAME* ]]; then
    return 0
  else
    return 1
  fi
}

check_if_ac() {
  local _ac_file="/sys/class/power_supply/AC/online"

  if ! $FSREAD_TOOL test -e "${_ac_file}"; then
    # We want to silently skip if AC file is not there. Most likely this is
    # not battery-powered device then.
    return 0
  fi

  while true; do
    ac_status=$($FSREAD_TOOL cat ${_ac_file})

    if [ "$ac_status" -eq 1 ]; then
      echo "AC adapter is connected. Continuing with firmware update."
      return
    else
      print_warning "Warning: AC adapter must be connected before performing firmware update."
      print_warning "Please connect the AC adapter and press 'C' to continue, or 'Q' to quit."

      read -n 1 -r input
      case $input in
       [Cc])
          echo "Checking AC status again..."
          ;;
        [Qq])
          echo "Quitting firmware update."
          return 1
          ;;
        *)
          echo "Invalid input. Press 'C' to continue, or 'Q' to quit."
          continue
          ;;
      esac
    fi
  done
}

### Error checks

# instead of error exit in dasharo-deploy exit we need to reboot the platform
# in cases where there would be some problem with updating the platform
fum_exit() {
    if [ "$FUM" == "fum" ]; then
      print_error "Update cannot be performed"
      print_warning "Starting bash session - please make sure you get logs from\r
      \r$ERR_LOG_FILE_REALPATH and $FLASHROM_LOG_FILE; then you can poweroff the platform"
      /bin/bash
    fi
}

error_exit() {
  _error_msg="$1"
  if [ -n "$_error_msg" ]; then
    # Avoid printing empty line if no message was passed
    print_error "$_error_msg"
  fi
  fum_exit
  exit 1
}

error_check() {
  _error_code=$?
  _error_msg="$1"
  [ "$_error_code" -ne 0 ] && error_exit "$_error_msg : ($_error_code)"
}

function error_file_check {
  if [ ! -f "$1" ]; then
    print_error "$2"
  fi
}

### Clevo-specific functions
# Method to access IT5570 IO Depth 2 registers
it5570_i2ec() {
  # TODO: Use /dev/port instead of iotools

  # Address high byte
  $IOTOOLS io_write8 0x2e 0x2e
  $IOTOOLS io_write8 0x2f 0x11
  $IOTOOLS io_write8 0x2e 0x2f
  $IOTOOLS io_write8 0x2f $(($2>>8 & 0xff))

  # Address low byte
  $IOTOOLS io_write8 0x2e 0x2e
  $IOTOOLS io_write8 0x2f 0x10
  $IOTOOLS io_write8 0x2e 0x2f
  $IOTOOLS io_write8 0x2f $(($2 & 0xff))

  # Data
  $IOTOOLS io_write8 0x2e 0x2e
  $IOTOOLS io_write8 0x2f 0x12
  $IOTOOLS io_write8 0x2e 0x2f

  case $1 in
    "r")
      $IOTOOLS io_read8 0x2f
      ;;
    "w")
      $IOTOOLS io_write8 0x2f "$3"
      ;;
  esac
}

it5570_shutdown() {
  # shut down using EC external watchdog reset
  it5570_i2ec w 0x1f01 0x20
  it5570_i2ec w 0x1f07 0x01
}

check_network_connection() {
  if wget --spider cloud.3mdeb.com > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

wait_for_network_connection() {
  echo 'Waiting for network connection ...'
  n="10"

  while : ; do
    if check_network_connection; then
      print_ok "Network connection have been established!"
      return 0
    fi

    n=$((n-1))
    if [ "${n}" == "0" ]; then
      print_error "Could not connect to network, please check network connection!"
      return 1
    fi
    sleep 1
  done
}

ask_for_model() {
  local model=( "$@" )
  if [ $# -lt 1 ]; then
    BOARD_MODEL=""
    return
  fi

  while :; do
    echo "Choose your board model:"
    echo "  0. None below"
    for ((i=0; i < $#; i++)); do
      echo "  $((i + 1)): ${model[$i]}"
    done

    echo
    read -r -p "Enter an option: " OPTION
    echo

    if [ "$OPTION" -eq 0 ]; then
      BOARD_MODEL=""
      return
    fi
    if [ "$OPTION" -gt 0 ] && [ "$OPTION" -le $# ]; then
      BOARD_MODEL="${model[$((OPTION - 1))]}"
      return
    fi
  done
}

board_config() {
# This functions checks used platform and configure environment in case the
# platform is supported. The supported platforms are sorted by variables
# SYSTEM_VENDOR, SYSTEM_MODEL, and BOARD_MODEL in switch/case statements.
#
# Every platform uses some standard environment configuration variables
# described in dts-environment.sh file, these could be specified for a specific
# board or vendor or shared between some, some platforms may have their own env.
# var. as well.
#
# All the standard variables are explicitly declared in dts-environment.sh
# script and, if appropriate, set to default values. If a platform has its own
# configuration variables - it must declare them here, even if they are not
# set. This is made with a goal to limit global variables declaration to
# dts-environment.sh and board_config function.

  # We download firmwares via network. At this point, the network connection
  # must be up already.
  wait_for_network_connection

  echo "Checking if board is Dasharo compatible."
  case "$SYSTEM_VENDOR" in
    "Notebook")
      # Common settings for all Notebooks:
      CAN_USE_FLASHROM="true"
      HAVE_EC="true"
      NEED_EC_RESET="true"
      PLATFORM_SIGN_KEY="customer-keys/novacustom/novacustom-open-source-firmware-release-1.x-key.asc \
        customer-keys/novacustom/dasharo-release-0.9.x-for-novacustom-signing-key.asc"
      NEED_SMMSTORE_MIGRATION="true"

      case "$SYSTEM_MODEL" in
        "NV4XMB,ME,MZ")
          DASHARO_REL_NAME="novacustom_nv4x_tgl"
          DASHARO_REL_VER="1.5.2"
          CAN_INSTALL_BIOS="true"
          COMPATIBLE_EC_FW_VERSION="2022-10-07_c662165"
          if check_if_dasharo; then
          # if v1.5.1 or older, flash the whole bios region
          # TODO: Let DTS determine which parameters are suitable.
          # FIXME: Can we ever get rid of that? We change so much in each release,
          # that we almost always need to flash whole BIOS regions
          # because of non-backward compatible or breaking changes.
            compare_versions $DASHARO_VERSION 1.5.2
            if [ $? -eq 1 ]; then
              # For Dasharo version lesser than 1.5.2
              NEED_BOOTSPLASH_MIGRATION="true"
              FLASHROM_ADD_OPT_UPDATE_OVERRIDE="--ifd -i bios"
            fi
          fi
          ;;
        "NS50_70MU")
          DASHARO_REL_NAME="novacustom_ns5x_tgl"
          DASHARO_REL_VER="1.5.2"
          CAN_INSTALL_BIOS="true"
          COMPATIBLE_EC_FW_VERSION="2022-08-31_cbff21b"
          PROGRAMMER_EC="ite_ec:romsize=128K,autoload=disable"
          if check_if_dasharo; then
          # if v1.5.1 or older, flash the whole bios region
          # TODO: Let DTS determine which parameters are suitable.
          # FIXME: Can we ever get rid of that? We change so much in each release,
          # that we almost always need to flash whole BIOS regions
          # because of non-backward compatible or breaking changes.
            compare_versions $DASHARO_VERSION 1.5.2
            if [ $? -eq 1 ]; then
              # For Dasharo version lesser than 1.5.2
              NEED_BOOTSPLASH_MIGRATION="true"
              FLASHROM_ADD_OPT_UPDATE_OVERRIDE="--ifd -i bios"
            fi
          fi
          ;;
        "NS5x_NS7xPU")
          DASHARO_REL_NAME="novacustom_ns5x_adl"
          DASHARO_REL_VER="1.7.2"
          COMPATIBLE_EC_FW_VERSION="2022-08-31_cbff21b"
          if check_if_dasharo; then
          # if v1.7.2 or older, flash the whole bios region
          # TODO: Let DTS determine which parameters are suitable.
          # FIXME: Can we ever get rid of that? We change so much in each release,
          # that we almost always need to flash whole BIOS regions
          # because of non-backward compatible or breaking changes.
            compare_versions $DASHARO_VERSION 1.7.2
            if [ $? -eq 1 ]; then
              # For Dasharo version lesser than 1.7.2
              NEED_BOOTSPLASH_MIGRATION="true"
              FLASHROM_ADD_OPT_UPDATE_OVERRIDE="--ifd -i bios"
            fi
          fi
          ;;
        "NV4xPZ")
          DASHARO_REL_NAME="novacustom_nv4x_adl"
          DASHARO_REL_VER="1.7.2"
          HEADS_REL_VER_DPP="0.9.1"
          HEADS_LINK_DPP="${FW_STORE_URL_DPP}/${DASHARO_REL_NAME}/v${HEADS_REL_VER_DPP}/${DASHARO_REL_NAME}_v${HEADS_REL_VER_DPP}_heads.rom"
          HEADS_SWITCH_FLASHROM_OPT_OVERRIDE="--ifd -i bios"
          COMPATIBLE_EC_FW_VERSION="2022-08-31_cbff21b"
          if check_if_dasharo; then
          # if v1.7.2 or older, flash the whole bios region
          # TODO: Let DTS determine which parameters are suitable.
          # FIXME: Can we ever get rid of that? We change so much in each release,
          # that we almost always need to flash whole BIOS regions
          # because of non-backward compatible or breaking changes.
            compare_versions $DASHARO_VERSION 1.7.2
            if [ $? -eq 1 ]; then
              # For Dasharo version lesser than 1.7.2
              NEED_BOOTSPLASH_MIGRATION="true"
              FLASHROM_ADD_OPT_UPDATE_OVERRIDE="--ifd -i bios"
            else
              HAVE_HEADS_FW="true"
            fi
            if [ "$DASHARO_FLAVOR" == "Dasharo (coreboot+heads)" ]; then
              HAVE_HEADS_FW="true"
            fi
          fi
          ;;
        "V54x_6x_TU")
          # Dasharo 0.9.0-rc10 and higher have board model in baseboard-version
          if check_if_dasharo && compare_versions "$DASHARO_VERSION" 0.9.0-rc10; then
            BOARD_MODEL="$($DMIDECODE dump_var_mock -s baseboard-version)"
          elif ! $DASHARO_ECTOOL check_for_opensource_firm_mock info 2>/dev/null; then
            ask_for_model V540TU V560TU
          else
            BOARD_MODEL=$($DASHARO_ECTOOL novacustom_check_sys_model_mock info | grep "board:" |
              sed -r 's|.*novacustom/(.*)|\1|' | awk '{print toupper($1)}')
          fi

          # Common configuration for all V54x_6x_TU:
          DASHARO_REL_VER="0.9.0"
          COMPATIBLE_EC_FW_VERSION="2024-07-17_4ae73b9"
          NEED_BOOTSPLASH_MIGRATION="true"

          case $BOARD_MODEL in
            "V540TU")
              DASHARO_REL_NAME="novacustom_v54x_mtl"
              FLASHROM_ADD_OPT_UPDATE_OVERRIDE="--ifd -i bios"
              ;;
            "V560TU")
              DASHARO_REL_NAME="novacustom_v56x_mtl"
              FLASHROM_ADD_OPT_UPDATE_OVERRIDE="--ifd -i bios"
              ;;
            *)
              print_error "Board model $BOARD_MODEL is currently not supported"
              return 1
              ;;
          esac
          ;;
        "V5xTNC_TND_TNE")
          if check_if_dasharo; then
            BOARD_MODEL="$($DMIDECODE dump_var_mock -s baseboard-version)"
          else
            ask_for_model V540TNx V560TNx
          fi

          NEED_BOOTSPLASH_MIGRATION="true"

          case $BOARD_MODEL in
            "V540TNx")
              DASHARO_REL_NAME="novacustom_v54x_mtl"
              DASHARO_REL_VER="0.9.1"
              COMPATIBLE_EC_FW_VERSION="2024-09-10_3786c8c"
              FLASHROM_ADD_OPT_UPDATE_OVERRIDE="--ifd -i bios"
              ;;
            "V560TNx")
              DASHARO_REL_NAME="novacustom_v56x_mtl"
              DASHARO_REL_VER="0.9.1"
              COMPATIBLE_EC_FW_VERSION="2024-09-10_3786c8c"
              FLASHROM_ADD_OPT_UPDATE_OVERRIDE="--ifd -i bios"
              ;;
            *)
              print_error "Board model $BOARD_MODEL is currently not supported"
              return 1
              ;;
          esac
          ;;
        *)
          print_error "Board model $SYSTEM_MODEL is currently not supported"
          return 1
          ;;
      esac
      BIOS_LINK_COMM="$FW_STORE_URL/$DASHARO_REL_NAME/v$DASHARO_REL_VER/${DASHARO_REL_NAME}_v${DASHARO_REL_VER}.rom"
      EC_LINK_COMM="$FW_STORE_URL/$DASHARO_REL_NAME/v$DASHARO_REL_VER/${DASHARO_REL_NAME}_ec_v${DASHARO_REL_VER}.rom"
      ;;
    "Micro-Star International Co., Ltd.")
      case "$SYSTEM_MODEL" in
        "MS-7D25")
          # Common configuration for all MS-7D25:
          DASHARO_REL_NAME="msi_ms7d25"
          DASHARO_REL_VER="1.1.1"
          DASHARO_REL_VER_DPP="1.1.4"
          CAN_INSTALL_BIOS="true"
          HAVE_HEADS_FW="true"
          HEADS_REL_VER_DPP="0.9.0"
          HEADS_SWITCH_FLASHROM_OPT_OVERRIDE="--ifd -i bios"
          PLATFORM_SIGN_KEY="dasharo/msi_ms7d25/dasharo-release-1.x-compatible-with-msi-ms-7d25-signing-key.asc \
             dasharo/msi_ms7d25/dasharo-release-0.x-compatible-with-msi-ms-7d25-signing-key.asc"
          NEED_SMBIOS_MIGRATION="true"
          NEED_SMMSTORE_MIGRATION="true"
          NEED_ROMHOLE_MIGRATION="true"

          # Add capsules:
          DASHARO_REL_NAME_CAP="$DASHARO_REL_NAME"
          DASHARO_REL_VER_DPP_CAP="$DASHARO_REL_VER_DPP"
          DASHARO_SUPPORT_CAP_FROM="1.1.4"

          # flash the whole bios region
          # TODO: Let DTS determine which parameters are suitable.
          # FIXME: Can we ever get rid of that? We change so much in each release,
          # that we almost always need to flash whole BIOS region
          # because of non-backward compatible or breaking changes.
          NEED_BOOTSPLASH_MIGRATION="true"
          FLASHROM_ADD_OPT_UPDATE_OVERRIDE="--ifd -i bios"

          case "$BOARD_MODEL" in
            "PRO Z690-A WIFI DDR4(MS-7D25)" | "PRO Z690-A DDR4(MS-7D25)")
              BIOS_LINK_COMM="${FW_STORE_URL}/${DASHARO_REL_NAME}/v${DASHARO_REL_VER}/${DASHARO_REL_NAME}_v${DASHARO_REL_VER}_ddr4.rom"
              BIOS_LINK_DPP="${FW_STORE_URL_DPP}/MS-7D25/v${DASHARO_REL_VER_DPP}/${DASHARO_REL_NAME}_v${DASHARO_REL_VER_DPP}_ddr4.rom"
              BIOS_LINK_DPP_CAP="${FW_STORE_URL_DPP}/MS-7D25/v${DASHARO_REL_VER_DPP_CAP}/${DASHARO_REL_NAME_CAP}_v${DASHARO_REL_VER_DPP_CAP}_ddr4.cap"
              HEADS_LINK_DPP="${FW_STORE_URL_DPP}/MS-7D25/v${HEADS_REL_VER_DPP}/${DASHARO_REL_NAME}_v${HEADS_REL_VER_DPP}_ddr4_heads.rom"
              ;;
            "PRO Z690-A WIFI (MS-7D25)" | "PRO Z690-A (MS-7D25)")
              BIOS_LINK_COMM="${FW_STORE_URL}/${DASHARO_REL_NAME}/v${DASHARO_REL_VER}/${DASHARO_REL_NAME}_v${DASHARO_REL_VER}_ddr5.rom"
              BIOS_LINK_DPP="${FW_STORE_URL_DPP}/MS-7D25/v${DASHARO_REL_VER_DPP}/${DASHARO_REL_NAME}_v${DASHARO_REL_VER_DPP}_ddr5.rom"
              BIOS_LINK_DPP_CAP="${FW_STORE_URL_DPP}/MS-7D25/v${DASHARO_REL_VER_DPP_CAP}/${DASHARO_REL_NAME_CAP}_v${DASHARO_REL_VER_DPP_CAP}_ddr5.cap"
              HEADS_LINK_DPP="${FW_STORE_URL_DPP}/MS-7D25/v${HEADS_REL_VER_DPP}/${DASHARO_REL_NAME}_v${HEADS_REL_VER_DPP}_ddr5_heads.rom"
              ;;
            *)
              print_error "Board model $BOARD_MODEL is currently not supported"
              return 1
              ;;
          esac
          ;;
        "MS-7E06")
          # Common configuration for all MS-7E06:
          DASHARO_REL_NAME="msi_ms7e06"
          #DASHARO_REL_VER=""
          DASHARO_REL_VER_DPP="0.9.2"
          CAN_INSTALL_BIOS="true"
          HAVE_HEADS_FW="true"
          HEADS_REL_VER_DPP="0.9.0"
          HEADS_SWITCH_FLASHROM_OPT_OVERRIDE="--ifd -i bios"
          PLATFORM_SIGN_KEY="dasharo/msi_ms7e06/dasharo-release-0.x-compatible-with-msi-ms-7e06-signing-key.asc"
          NEED_SMMSTORE_MIGRATION="true"
          NEED_ROMHOLE_MIGRATION="true"

          # Add capsules:
          DASHARO_REL_NAME_CAP="$DASHARO_REL_NAME"
          DASHARO_REL_VER_DPP_CAP="$DASHARO_REL_VER_DPP"
          DASHARO_SUPPORT_CAP_FROM="0.9.2"

          # flash the whole bios region
          # TODO: Let DTS determine which parameters are suitable.
          # FIXME: Can we ever get rid of that? We change so much in each release,
          # that we almost always need to flash whole BIOS region
          # because of non-backward compatible or breaking changes.
          NEED_BOOTSPLASH_MIGRATION="true"
          FLASHROM_ADD_OPT_UPDATE_OVERRIDE="--ifd -i bios"

          case "$BOARD_MODEL" in
            "PRO Z790-P WIFI DDR4(MS-7E06)" | "PRO Z790-P DDR4(MS-7E06)" | "PRO Z790-P WIFI DDR4 (MS-7E06)" | "PRO Z790-P DDR4 (MS-7E06)")
              #BIOS_LINK_COMM="$FW_STORE_URL/$DASHARO_REL_NAME/v$DASHARO_REL_VER/${DASHARO_REL_NAME}_v${DASHARO_REL_VER}_ddr4.rom"
              BIOS_LINK_DPP="${FW_STORE_URL_DPP}/MS-7E06/v${DASHARO_REL_VER_DPP}/${DASHARO_REL_NAME}_v${DASHARO_REL_VER_DPP}_ddr4.rom"
              BIOS_LINK_DPP_CAP="${FW_STORE_URL_DPP}/MS-7E06/v${DASHARO_REL_VER_DPP_CAP}/${DASHARO_REL_NAME_CAP}_v${DASHARO_REL_VER_DPP_CAP}_ddr4.cap"
              HEADS_LINK_DPP="${FW_STORE_URL_DPP}/MS-7E06/v${HEADS_REL_VER_DPP}/${DASHARO_REL_NAME}_v${HEADS_REL_VER_DPP}_ddr4_heads.rom"
              PROGRAMMER_BIOS="internal:boardmismatch=force"
              ;;
            "PRO Z790-P WIFI (MS-7E06)" | "PRO Z790-P (MS-7E06)")
              #BIOS_LINK_COMM="$FW_STORE_URL/$DASHARO_REL_NAME/v$DASHARO_REL_VER/${DASHARO_REL_NAME}_v${DASHARO_REL_VER}_ddr5.rom"
              BIOS_LINK_DPP="${FW_STORE_URL_DPP}/MS-7E06/v${DASHARO_REL_VER_DPP}/${DASHARO_REL_NAME}_v${DASHARO_REL_VER_DPP}_ddr5.rom"
              BIOS_LINK_DPP_CAP="${FW_STORE_URL_DPP}/MS-7E06/v${DASHARO_REL_VER_DPP_CAP}/${DASHARO_REL_NAME_CAP}_v${DASHARO_REL_VER_DPP_CAP}_ddr5.cap"
              HEADS_LINK_DPP="${FW_STORE_URL_DPP}/MS-7E06/v${HEADS_REL_VER_DPP}/${DASHARO_REL_NAME}_v${HEADS_REL_VER_DPP}_ddr5_heads.rom"
              ;;
            *)
              print_error "Board model $BOARD_MODEL is currently not supported"
              return 1
              ;;
          esac
          ;;
        *)
          print_error "Board model $SYSTEM_MODEL is currently not supported"
          return 1
          ;;
      esac
      ;;
    "Dell Inc.")
      # Common configuration for all Dell releases:
      DASHARO_REL_NAME="dell_optiplex_7010_9010"
      DASHARO_REL_VER_DPP="0.1.1"
      BIOS_LINK_DPP="$FW_STORE_URL_DPP/v$DASHARO_REL_VER_DPP/${DASHARO_REL_NAME}_v$DASHARO_REL_VER_DPP.rom"
      CAN_INSTALL_BIOS="true"
      NEED_SMBIOS_MIGRATION="true"
      NEED_BLOB_TRANSMISSION="true"
      SINIT_ACM_FILENAME="/tmp/630744_003.zip"
      SINIT_ACM_URL="https://cdrdv2.intel.com/v1/dl/getContent/630744"
      SINIT_ACM_HASH="0b412c1832bd504d4b8f5fa01b32449c344fe0019e5e4da6bb5d80d393df5e8b $SINIT_ACM_FILENAME"
      SINIT_ACM="/tmp/630744_003/SNB_IVB_SINIT_20190708_PW.bin"
      FLASHROM_ADD_OPT_DEPLOY="--ifd -i bios"
      FLASHROM_ADD_OPT_UPDATE="--fmap -i RW_SECTION_A"

      case "$SYSTEM_MODEL" in
        "OptiPlex 7010")
          DBT_BIOS_UPDATE_FILENAME="/tmp/O7010A29.exe"
          DBT_BIOS_UPDATE_URL="https://dl.dell.com/FOLDER05066036M/1/O7010A29.exe"
          DBT_BIOS_UPDATE_HASH="ceb82586c67cd8d5933ac858c12e0cb52f6e0e4cb3249f964f1c0cfc06d16f52  $DBT_BIOS_UPDATE_FILENAME"
          DBT_UEFI_IMAGE="/tmp/_O7010A29.exe.extracted/65C10"
          SCH5545_FW="/tmp/_O7010A29.exe.extracted/65C10_output/pfsobject/section-7ec6c2b0-3fe3-42a0-a316-22dd0517c1e8/volume-0x50000/file-d386beb8-4b54-4e69-94f5-06091f67e0d3/section0.raw"
          ACM_BIN="/tmp/_O7010A29.exe.extracted/65C10_output/pfsobject/section-7ec6c2b0-3fe3-42a0-a316-22dd0517c1e8/volume-0x500000/file-2d27c618-7dcd-41f5-bb10-21166be7e143/object-0.raw"
          ;;
        "OptiPlex 9010")
          DBT_BIOS_UPDATE_FILENAME="/tmp/O9010A30.exe"
          DBT_BIOS_UPDATE_URL="https://dl.dell.com/FOLDER05066009M/1/O9010A30.exe"
          DBT_BIOS_UPDATE_HASH="b11952f43d0ad66f3ce79558b8c5dd43f30866158ed8348e3b2dae1bbb07701b  $DBT_BIOS_UPDATE_FILENAME"
          DBT_UEFI_IMAGE="/tmp/_O9010A30.exe.extracted/65C10"
          SCH5545_FW="/tmp/_O9010A30.exe.extracted/65C10_output/pfsobject/section-7ec6c2b0-3fe3-42a0-a316-22dd0517c1e8/volume-0x50000/file-d386beb8-4b54-4e69-94f5-06091f67e0d3/section0.raw"
          ACM_BIN="/tmp/_O9010A30.exe.extracted/65C10_output/pfsobject/section-7ec6c2b0-3fe3-42a0-a316-22dd0517c1e8/volume-0x500000/file-2d27c618-7dcd-41f5-bb10-21166be7e143/object-0.raw"
          ;;
        "Precision T1650")
          # tested on Dasharo Firmware for OptiPlex 9010, will need to be
          # enabled when build for T1650 exists
          #
          # DBT_BIOS_UPDATE_FILENAME="/tmp/T1650A28.exe"
          # DBT_BIOS_UPDATE_URL="https://dl.dell.com/FOLDER05065992M/1/T1650A28.exe"
          # DBT_BIOS_UPDATE_HASH="40a66210b8882f523885849c1d879e726dc58aa14718168b1e75f3e2caaa523b  $DBT_BIOS_UPDATE_FILENAME"
          # DBT_UEFI_IMAGE="/tmp/_T1650A28.exe.extracted/65C10"
          # SCH5545_FW="/tmp/_T1650A28.exe.extracted/65C10_output/pfsobject/section-7ec6c2b0-3fe3-42a0-a316-22dd0517c1e8/volume-0x60000/file-d386beb8-4b54-4e69-94f5-06091f67e0d3/section0.raw"
          # ACM_BIN="/tmp/_T1650A28.exe.extracted/65C10_output/pfsobject/section-7ec6c2b0-3fe3-42a0-a316-22dd0517c1e8/volume-0x500000/file-2d27c618-7dcd-41f5-bb10-21166be7e143/object-0.raw"
          print_warning "Dasharo Firmware for Precision T1650 not available yet!"
          print_error "Board model $SYSTEM_MODEL is currently not supported"
          return 1
          ;;
        *)
          print_error "Board model $SYSTEM_MODEL is currently not supported"
          return 1
          ;;
      esac
      ;;
    "ASUS")
      case "$SYSTEM_MODEL" in
        "KGPE-D16")
          DASHARO_REL_NAME="asus_kgpe-d16"
          DASHARO_REL_VER="0.4.0"
          CAN_INSTALL_BIOS="true"
          case "$FLASH_CHIP_SIZE" in
          "2")
            BIOS_HASH_LINK_COMM="65e5370e9ea6b8ae7cd6cc878a031a4ff3a8f5d36830ef39656b8e5a6e37e889  $BIOS_UPDATE_FILE"
            BIOS_LINK_COMM="$FW_STORE_URL/$DASHARO_REL_NAME/v$DASHARO_REL_VER/${DASHARO_REL_NAME}_v${DASHARO_REL_VER}_vboot_notpm.rom"
            ;;
          "8")
            BIOS_HASH_LINK_COMM="da4e6217d50f2ac199dcb9a927a0bc02aa4e792ed73c8c9bac8ba74fc787dbef  $BIOS_UPDATE_FILE"
            BIOS_LINK_COMM="$FW_STORE_URL/$DASHARO_REL_NAME/v$DASHARO_REL_VER/${DASHARO_REL_NAME}_v${DASHARO_REL_VER}_${FLASH_CHIP_SIZE}M_vboot_notpm.rom"
            ;;
          "16")
            BIOS_HASH_LINK_COMM="20055cf57185f149259706f58d5e9552a1589259c6617999c1ac7d8d3c960020  $BIOS_UPDATE_FILE"
            BIOS_LINK_COMM="$FW_STORE_URL/$DASHARO_REL_NAME/v$DASHARO_REL_VER/${DASHARO_REL_NAME}_v${DASHARO_REL_VER}_${FLASH_CHIP_SIZE}M_vboot_notpm.rom"
            ;;
          *)
            print_error "Platform uses chipset with not supported size"
            return 1
            ;;
          esac
          NEED_SMBIOS_MIGRATION="true"
          ;;
        *)
          print_error "Board model $SYSTEM_MODEL is currently not supported"
          return 1
          ;;
      esac
      ;;
    "PC Engines")
      # Common configuration for all PC Engines releases:
      DASHARO_REL_VER_DPP="0.9.0"
      CAN_INSTALL_BIOS="true"
      DASHARO_REL_VER_DPP_SEABIOS="24.05.00.01"
      PROGRAMMER_BIOS="internal:boardmismatch=force"
      NEED_SMMSTORE_MIGRATION="true"
      NEED_BOOTSPLASH_MIGRATION="true"
      FLASH_CHIP_LIST="W25Q64JV-.Q"

      shopt -s nocasematch
      case "$SYSTEM_MODEL" in
        "APU2")
          DASHARO_REL_NAME="pcengines_apu2"
          ;;
        "APU3")
          DASHARO_REL_NAME="pcengines_apu3"
          ;;
        "APU4")
          DASHARO_REL_NAME="pcengines_apu4"
          ;;
        "APU6")
          DASHARO_REL_NAME="pcengines_apu6"
          ;;
        *)
          print_error "Board model $SYSTEM_MODEL is currently not supported"
          return 1
          ;;
      esac

      BIOS_LINK_DPP="${FW_STORE_URL_DPP}/pcengines_apu2/v${DASHARO_REL_VER_DPP}/${DASHARO_REL_NAME}_v${DASHARO_REL_VER_DPP}.rom"
      BIOS_LINK_DPP_SEABIOS="${FW_STORE_URL_DPP}/pcengines_apu2/v${DASHARO_REL_VER_DPP_SEABIOS}/${DASHARO_REL_NAME}_seabios_v${DASHARO_REL_VER_DPP_SEABIOS}.rom"

      shopt -u nocasematch
      ;;
    "HARDKERNEL")
      NEED_SMBIOS_MIGRATION="true"

      case "$SYSTEM_MODEL" in
        "ODROID-H4")
          PLATFORM_SIGN_KEY="dasharo/hardkernel_odroid_h4/dasharo-release-0.x-compatible-with-hardkernel-odroid-h4-family-signing-key.asc"
          DASHARO_REL_NAME="hardkernel_odroid_h4"
          DASHARO_REL_VER_DPP="0.9.0"
          ;;
        *)
          print_error "Board model $SYSTEM_MODEL is currently not supported"
          return 1
          ;;
      esac

      BIOS_LINK_DPP="$FW_STORE_URL_DPP/$DASHARO_REL_NAME/v$DASHARO_REL_VER_DPP/${DASHARO_REL_NAME}_v$DASHARO_REL_VER_DPP.rom"
      ;;
    "QEMU"|"Emulation")
      case "$SYSTEM_MODEL" in
        *Q35*ICH9*|*q35*ich9*)
           # Update type:
           CAN_INSTALL_BIOS="true"
           # Download and versioning variables:
           DASHARO_REL_NAME_CAP="qemu_q35"
           DASHARO_REL_VER_CAP="0.2.0"
           DASHARO_SUPPORT_CAP_FROM="0.2.0"
           # TODO: wait till the binaries will be uploaded to the server.
           BIOS_LINK_COMM_CAP="${FW_STORE_URL}/${DASHARO_REL_NAME_CAP}/v${DASHARO_REL_VER_CAP}/"
	  ;;
        *)
          print_error "Board model $SYSTEM_MODEL is currently not supported"
	  return 1
	  ;;
      esac
      ;;
    *)
      print_error "Board vendor: $SYSTEM_VENDOR is currently not supported"
      return 1
      ;;
  esac

  # Set some default values at the end:
  [ -z "$BIOS_HASH_LINK_COMM" ] && BIOS_HASH_LINK_COMM="${BIOS_LINK_COMM}.sha256"
  [ -z "$BIOS_SIGN_LINK_COMM" ] && BIOS_SIGN_LINK_COMM="${BIOS_HASH_LINK_COMM}.sig"
  [ -z "$BIOS_HASH_LINK_DPP" ] && BIOS_HASH_LINK_DPP="${BIOS_LINK_DPP}.sha256"
  [ -z "$BIOS_SIGN_LINK_DPP" ] && BIOS_SIGN_LINK_DPP="${BIOS_HASH_LINK_DPP}.sig"
  [ -z "$BIOS_HASH_LINK_DPP_SEABIOS" ] && BIOS_HASH_LINK_DPP_SEABIOS="${BIOS_LINK_DPP_SEABIOS}.sha256"
  [ -z "$BIOS_SIGN_LINK_DPP_SEABIOS" ] && BIOS_SIGN_LINK_DPP_SEABIOS="${BIOS_HASH_LINK_DPP_SEABIOS}.sig"
  [ -z "$HEADS_HASH_LINK_DPP" ] && HEADS_HASH_LINK_DPP="${HEADS_LINK_DPP}.sha256"
  [ -z "$HEADS_SIGN_LINK_DPP" ] && HEADS_SIGN_LINK_DPP="${HEADS_HASH_LINK_DPP}.sig"
  [ -z "$EC_HASH_LINK_COMM" ] && EC_HASH_LINK_COMM="${EC_LINK_COMM}.sha256"
  [ -z "$EC_SIGN_LINK_COMM" ] && EC_SIGN_LINK_COMM="${EC_HASH_LINK_COMM}.sig"
  [ -z "$EC_HASH_LINK_DPP" ] && EC_HASH_LINK_DPP="${EC_LINK_DPP}.sha256"
  [ -z "$EC_SIGN_LINK_DPP" ] && EC_SIGN_LINK_DPP="${EC_HASH_LINK_DPP}.sig"

  # And for capsules as well:
  [ -z "$BIOS_HASH_LINK_COMM_CAP" ] && BIOS_HASH_LINK_COMM_CAP="${BIOS_LINK_COMM_CAP}.sha256"
  [ -z "$BIOS_SIGN_LINK_COMM_CAP" ] && BIOS_SIGN_LINK_COMM_CAP="${BIOS_HASH_LINK_COMM_CAP}.sig"
  [ -z "$BIOS_HASH_LINK_DPP_CAP" ] && BIOS_HASH_LINK_DPP_CAP="${BIOS_LINK_DPP_CAP}.sha256"
  [ -z "$BIOS_SIGN_LINK_DPP_CAP" ] && BIOS_SIGN_LINK_DPP_CAP="${BIOS_HASH_LINK_DPP_CAP}.sig"
  [ -z "$EC_HASH_LINK_COMM_CAP" ] && EC_HASH_LINK_COMM_CAP="${EC_LINK_COMM_CAP}.sha256"
  [ -z "$EC_SIGN_LINK_COMM_CAP" ] && EC_SIGN_LINK_COMM_CAP="${EC_HASH_LINK_COMM_CAP}.sig"
  [ -z "$EC_HASH_LINK_DPP_CAP" ] && EC_HASH_LINK_DPP_CAP="${EC_LINK_DPP_CAP}.sha256"
  [ -z "$EC_SIGN_LINK_DPP_CAP" ] && EC_SIGN_LINK_DPP_CAP="${EC_HASH_LINK_DPP_CAP}.sig"
}

check_flash_lock() {
    $FLASHROM check_flash_lock_mock -p "$PROGRAMMER_BIOS" ${FLASH_CHIP_SELECT} > /tmp/check_flash_lock 2> /tmp/check_flash_lock.err
    # Check in flashrom output if lock is enabled
    grep -q 'PR0: Warning:.* is read-only\|SMM protection is enabled' /tmp/check_flash_lock.err
    if [ $? -eq 0 ]; then
        print_warning "Flash lock enabled, please go into BIOS setup / Dasharo System Features / Dasharo\r
        \rSecurity Options and enable access to flash with flashrom.\r\n
        \rYou can learn more about this on: https://docs.dasharo.com/dasharo-menu-docs/dasharo-system-features/#dasharo-security-options"
        exit 1
    fi
}

check_flash_chip() {
  echo "Gathering flash chip and chipset information..."
  $FLASHROM flash_chip_name_mock -p "$PROGRAMMER_BIOS" --flash-name >> "$FLASH_INFO_FILE" 2>> "$ERR_LOG_FILE"
  if [ $? -eq 0 ]; then
    echo -n "Flash information: "
    tail -n1 "$FLASH_INFO_FILE"
    FLASH_CHIP_SIZE=$(($($FLASHROM flash_chip_size_mock -p "$PROGRAMMER_BIOS" --flash-size 2>> /dev/null | tail -n1) / 1024 / 1024))
    echo -n "Flash size: "
    echo ${FLASH_CHIP_SIZE}M
  else
    for flash_name in $FLASH_CHIP_LIST
    do
      $FLASHROM flash_chip_name_mock -p "$PROGRAMMER_BIOS" -c "$flash_name" --flash-name >> "$FLASH_INFO_FILE" 2>> "$ERR_LOG_FILE"
      if [ $? -eq 0 ]; then
        echo "Chipset found"
        tail -n1 "$FLASH_INFO_FILE"
        FLASH_CHIP_SELECT="-c ${flash_name}"
        FLASH_CHIP_SIZE=$(($($FLASHROM flash_chip_size_mock -p "$PROGRAMMER_BIOS" ${FLASH_CHIP_SELECT} --flash-size 2>> /dev/null | tail -n1) / 1024 / 1024))
        echo "Chipset size"
        echo ${FLASH_CHIP_SIZE}M
        break
      fi
    done
    if [ -z "$FLASH_CHIP_SELECT" ]; then
      error_exit "No supported chipset found, exit."
    fi
  fi
}

compare_versions() {
    # return 1 if ver2 > ver1
    # return 0 otherwise
    local ver1=
    local ver2=
    local compare=
    # convert version ending with '-rc<x>' to '-rc.<x>' where <x> is number
    # as semantic versioning compares whole 'rc<x>' as alphanumeric identifier
    # which results in rc2 > rc12. More information at https://semver.org/
    ver1=$(sed -r "s/-rc([0-9]+)$/-rc.\1/" <<< "$1")
    ver2=$(sed -r "s/-rc([0-9]+)$/-rc.\1/" <<< "$2")

    if ! python3 -m semver check "$ver1" || ! python3 -m semver check "$ver2"; then
      error_exit "Incorrect version format"
    fi
    compare=$(python3 -m semver compare "$ver1" "$ver2")
    if [ "$compare" -eq -1 ]; then
      return 1
    else
      return 0
    fi
}

download_bios() {
  if [ "${BIOS_LINK}" == "${BIOS_LINK_COMM}" ] || [ "${BIOS_LINK}" == "${BIOS_LINK_COMM_CAP}" ]; then
    curl -s -L -f "$BIOS_LINK" -o $BIOS_UPDATE_FILE
    error_check "Cannot access $FW_STORE_URL while downloading binary. Please
   check your internet connection"
    curl -s -L -f "$BIOS_HASH_LINK" -o $BIOS_HASH_FILE
    error_check "Cannot access $FW_STORE_URL while downloading signature. Please
   check your internet connection"
    curl -s -L -f "$BIOS_SIGN_LINK" -o $BIOS_SIGN_FILE
    error_check "Cannot access $FW_STORE_URL while downloading signature. Please
   check your internet connection"
  else
    USER_DETAILS="$CLOUDSEND_DOWNLOAD_URL:$CLOUDSEND_PASSWORD"
    curl -s -L -f -u "$USER_DETAILS" -H "$CLOUD_REQUEST" "$BIOS_LINK" -o $BIOS_UPDATE_FILE
    error_check "Cannot access $FW_STORE_URL_DPP while downloading binary.
   Please check your internet connection and credentials"
    curl -s -L -f -u "$USER_DETAILS" -H "$CLOUD_REQUEST" "$BIOS_HASH_LINK" -o $BIOS_HASH_FILE
    error_check "Cannot access $FW_STORE_URL_DPP while downloading signature.
   Please check your internet connection and credentials"
    curl -s -L -f -u "$USER_DETAILS" -H "$CLOUD_REQUEST" "$BIOS_SIGN_LINK" -o $BIOS_SIGN_FILE
    error_check "Cannot access $FW_STORE_URL_DPP while downloading signature.
   Please check your internet connection and credentials"
  fi
}

download_ec() {
  if [ "${BIOS_LINK}" = "${BIOS_LINK_COMM}" ] || [ "${BIOS_LINK}" = "${BIOS_LINK_COMM_CAP}" ]; then
    curl -s -L -f "$EC_LINK" -o "$EC_UPDATE_FILE"
    error_check "Cannot access $FW_STORE_URL while downloading binary. Please
     check your internet connection"
    curl -s -L -f "$EC_HASH_LINK" -o $EC_HASH_FILE
    error_check "Cannot access $FW_STORE_URL while downloading signature. Please
     check your internet connection"
    curl -s -L -f "$EC_SIGN_LINK" -o $EC_SIGN_FILE
    error_check "Cannot access $FW_STORE_URL while downloading signature. Please
     check your internet connection"
  else
    curl -s -L -f -u "$USER_DETAILS" -H "$CLOUD_REQUEST" "$EC_LINK" -o $EC_UPDATE_FILE
    error_check "Cannot access $FW_STORE_URL while downloading binary. Please
     check your internet connection and credentials"
    curl -s -L -f -u "$USER_DETAILS" -H "$CLOUD_REQUEST" "$EC_HASH_LINK" -o $EC_HASH_FILE
    error_check "Cannot access $FW_STORE_URL while downloading signature. Please
     check your internet connection and credentials"
    curl -s -L -f -u "$USER_DETAILS" -H "$CLOUD_REQUEST" "$EC_SIGN_LINK" -o $EC_SIGN_FILE
    error_check "Cannot access $FW_STORE_URL while downloading signature. Please
     check your internet connection and credentials"
  fi
}

download_keys() {
  mkdir $KEYS_DIR
  wget -O $KEYS_DIR/recovery_key.vbpubk https://github.com/Dasharo/vboot/raw/dasharo/tests/devkeys/recovery_key.vbpubk >> $ERR_LOG_FILE 2>&1
  wget -O $KEYS_DIR/firmware.keyblock https://github.com/Dasharo/vboot/raw/dasharo/tests/devkeys/firmware.keyblock >> $ERR_LOG_FILE 2>&1
  wget -O $KEYS_DIR/firmware_data_key.vbprivk https://github.com/Dasharo/vboot/raw/dasharo/tests/devkeys/firmware_data_key.vbprivk >> $ERR_LOG_FILE 2>&1
  wget -O $KEYS_DIR/kernel_subkey.vbpubk https://github.com/Dasharo/vboot/raw/dasharo/tests/devkeys/kernel_subkey.vbpubk >> $ERR_LOG_FILE 2>&1
  wget -O $KEYS_DIR/root_key.vbpubk https://github.com/Dasharo/vboot/raw/dasharo/tests/devkeys/root_key.vbpubk >> $ERR_LOG_FILE 2>&1
}

get_signing_keys() {
    local platform_keys=$PLATFORM_SIGN_KEY
    echo -n "Getting platform specific GPG key... "
    for key in $platform_keys; do
        wget -q https://raw.githubusercontent.com/3mdeb/3mdeb-secpack/master/$key -O - | gpg --import - >> $ERR_LOG_FILE 2>&1
        error_check "Cannot get $key key to verify signatures."
    done
    print_ok "Done"
}

verify_artifacts() {
# This function checks downloaded files, the files that are being downloaded
# should have hashes provided on the server too. The hashes will ben downloaded
# and the binaries will be verified upon them.
#
# In case of .rom files it will be enough but capsules have additional
# protection layer built in, the binaries they provide will be verified by
# drivers, so no need to implement it here.
  local _update_file=""
  local _hash_file=""
  local _sign_file=""
  local _name=""
  local _sig_result=""

  while [[ $# -gt 0 ]]; do
    local _type="$1"

    case $_type in
      ec)
        _update_file=$EC_UPDATE_FILE
        _hash_file=$EC_HASH_FILE
        _sign_file=$EC_SIGN_FILE
        _name="Dasharo EC"
	shift
        ;;
      bios)
        _update_file=$BIOS_UPDATE_FILE
        _hash_file=$BIOS_HASH_FILE
        _sign_file=$BIOS_SIGN_FILE
        _name="Dasharo"
	shift
        ;;
      *)
        error_exit "Unknown artifact type: $_type"
        ;;
    esac

    echo -n "Checking $_name firmware checksum... "
    sha256sum --check <(echo "$(cat $_hash_file | cut -d ' ' -f 1)" $_update_file) >> $ERR_LOG_FILE 2>&1
    error_check "Failed to verify $_name firmware checksum"
    print_ok "Verified."

    if [ -n "$PLATFORM_SIGN_KEY" ]; then
      echo -n "Checking $_name firmware signature... "
      _sig_result="$(cat $_hash_file | gpg --verify $_sign_file - >> $ERR_LOG_FILE 2>&1)"
      error_check "Failed to verify $_name firmware signature.$'\n'$_sig_result"
      print_ok "Verified."
    fi
    echo "$_sig_result"
  done

  return 0
}

check_intel_regions() {

  FLASH_REGIONS=$($FLASHROM check_intel_regions_mock -p "$PROGRAMMER_BIOS" ${FLASH_CHIP_SELECT} 2>&1)
  BOARD_HAS_FD_REGION=0
  BOARD_FD_REGION_RW=0
  BOARD_HAS_ME_REGION=0
  BOARD_ME_REGION_RW=0
  BOARD_ME_REGION_LOCKED=0
  BOARD_HAS_GBE_REGION=0
  BOARD_GBE_REGION_RW=0
  BOARD_GBE_REGION_LOCKED=0

  grep -q "Flash Descriptor region" <<< "$FLASH_REGIONS" && BOARD_HAS_FD_REGION=1
  grep -qE "Flash Descriptor region.*read-write" <<< "$FLASH_REGIONS" && BOARD_FD_REGION_RW=1

  grep -q "Management Engine region" <<< "$FLASH_REGIONS" && BOARD_HAS_ME_REGION=1
  grep -qE "Management Engine region.*read-write" <<< "$FLASH_REGIONS" && BOARD_ME_REGION_RW=1
  grep -qE "Management Engine region.*locked" <<<  "$FLASH_REGIONS" && BOARD_ME_REGION_LOCKED=1

  grep -q "Gigabit Ethernet region" <<<  "$FLASH_REGIONS" && BOARD_HAS_GBE_REGION=1
  grep -qE "Gigabit Ethernet region.*read-write" <<<  "$FLASH_REGIONS" && BOARD_GBE_REGION_RW=1
  grep -qE "Gigabit Ethernet region.*locked" <<< "$FLASH_REGIONS" && BOARD_GBE_REGION_LOCKED=1
}

check_blobs_in_binary() {
  BINARY_HAS_FD=0
  BINARY_HAS_ME=0

  # If there is no descriptor, there is no ME as well, so skip the check
  if [ $BOARD_HAS_FD_REGION -ne 0 ]; then
    ME_OFFSET=$($IFDTOOL check_blobs_in_binary_mock -d $1 2>>"$ERR_LOG_FILE" | grep "Flash Region 2 (Intel ME):" | sed 's/Flash Region 2 (Intel ME)\://' | awk '{print $1;}')
    # Check for IFD signature at offset 0 (old descriptors)
    if [ "$(tail -c +0 $1|head -c 4|xxd -ps)" == "5aa5f00f" ]; then
      BINARY_HAS_FD=1
    fi
    # Check for IFD signature at offset 16 (new descriptors)
    if [ "$(tail -c +17 $1|head -c 4|xxd -ps)" == "5aa5f00f" ]; then
      BINARY_HAS_FD=1
    fi
    # Check for ME FPT signature at ME offset + 16 (old ME)
    if [ "$(tail -c +$((0x$ME_OFFSET + 17)) $1|head -c 4|tr -d '\0')" == "\$FPT" ]; then
      BINARY_HAS_ME=1
    fi
    # Check for aa55 signature at ME offset + 4096 (new ME)
    if [ "$(tail -c +$((0x$ME_OFFSET + 4097)) $1|head -c 2|xxd -ps)" == "aa55" ]; then
      BINARY_HAS_ME=1
    fi
  fi
}

check_if_me_disabled() {

  ME_DISABLED=0

  if [ $BOARD_HAS_ME_REGION -eq 0 ]; then
    # No ME region
    ME_DISABLED=1
    return
  fi

  if check_if_heci_present; then
    ME_OPMODE="$(check_me_op_mode)"
    if [ $ME_OPMODE == "0" ]; then
      echo "ME is not disabled"  >> $ERR_LOG_FILE
      return
    elif [ $ME_OPMODE == "2" ]; then
      echo "ME is disabled (HAP/Debug Mode)"  >> $ERR_LOG_FILE
      ME_DISABLED=1
      return
    elif [ $ME_OPMODE == "3" ]; then
      echo "ME is soft disabled (HECI)"  >> $ERR_LOG_FILE
      ME_DISABLED=1
      return
    elif [ $ME_OPMODE == "4" ]; then
      echo "ME disabled by Security Override Jumper/FDOPS"  >> $ERR_LOG_FILE
      ME_DISABLED=1
      return
    elif [ $ME_OPMODE == "5" ]; then
      echo "ME disabled by Security Override MEI Message/HMRFPO"  >> $ERR_LOG_FILE
      ME_DISABLED=1
      return
    elif [ $ME_OPMODE == "6" ]; then
      echo "ME disabled by Security Override MEI Message/HMRFPO"  >> $ERR_LOG_FILE
      ME_DISABLED=1
      return
    elif [ $ME_OPMODE == "7" ]; then
      echo "ME disabled (Enhanced Debug Mode) or runs Ignition FW"  >> $ERR_LOG_FILE
      ME_DISABLED=1
      return
    else
      print_warning "Unknown ME operation mode, assuming enabled."
      echo "Unknown ME operation mode, assuming enabled."  >> $ERR_LOG_FILE
      return
    fi
  else
    # If we are running coreboot, check for status in logs
    $CBMEM check_if_me_disabled_mock -1 | grep -q "ME is disabled" && ME_DISABLED=1 && return # HECI (soft) disabled
    $CBMEM check_if_me_disabled_mock -1 | grep -q "ME is HAP disabled" && ME_DISABLED=1 && return # HAP disabled
    # TODO: If proprietary BIOS, then also try to check SMBIOS for ME FWSTS
    # BTW we could do the same in coreboot, expose FWSTS in SMBIOS before it
    # gets disabled
    print_warning "Can not determine if ME is disabled, assuming enabled."
    echo "Can not determine if ME is disabled, assuming enabled."  >> $ERR_LOG_FILE
  fi
}

force_me_update() {
    echo
    print_warning "Flashing ME when not in disabled state may cause unexpected power management issues."
    print_warning "Recovering from such state may require removal of AC power supply and resetting CMOS battery."
    print_warning "Keeping an older version of ME may cause a CPU to perform less efficient, e.g. if upgraded the CPU to a newer generation."
    print_warning "You have been warned."
  while : ; do
    echo
    read -r -p "Skip ME flashing and proceed with BIOS/firmware flashing/updating? (Y|n) " OPTION
    echo

    case ${OPTION} in
      yes|y|Y|Yes|YES)
        print_warning "Proceeding without ME flashing, because we were asked to."
        break
        ;;
      n|N)
        error_exit "Cancelling flashing process..."
        ;;
      *)
        ;;
    esac
  done
}

set_flashrom_update_params() {
  # Safe defaults which should always work
  if [ $BOARD_HAS_FD_REGION -eq 0 ]; then
    FLASHROM_ADD_OPT_UPDATE=""
  else
    FLASHROM_ADD_OPT_UPDATE="-N --ifd -i bios"
  fi
  BINARY_HAS_RW_B=1
  # We need to read whole binary (or BIOS region), otherwise cbfstool will
  # return different attributes for CBFS regions
  echo "Checking flash layout."
  $FLASHROM read_flash_layout_mock -p "$PROGRAMMER_BIOS" ${FLASH_CHIP_SELECT} ${FLASHROM_ADD_OPT_UPDATE} -r $BIOS_DUMP_FILE > /dev/null 2>&1
  if [ $? -eq 0 ] && [ -f "$BIOS_DUMP_FILE" ]; then
    BOARD_FMAP_LAYOUT=$($CBFSTOOL layout_mock $BIOS_DUMP_FILE layout -w 2>>"$ERR_LOG_FILE")
    BINARY_FMAP_LAYOUT=$($CBFSTOOL layout_mock $1 layout -w 2>>"$ERR_LOG_FILE")
    diff <(echo "$BOARD_FMAP_LAYOUT") <(echo "$BINARY_FMAP_LAYOUT") > /dev/null 2>&1
    # If layout is identical, perform standard update using FMAP only
    if [ $? -eq 0 ]; then
      # Simply update RW_A fmap region if exists
      grep -q "RW_SECTION_A" <<< $BINARY_FMAP_LAYOUT
      if [ $? -eq 0 ]; then
        FLASHROM_ADD_OPT_UPDATE="-N --fmap -i RW_SECTION_A -i WP_RO"
      else
        # RW_A does not exists, it means no vboot. Update COREBOOT region only
        FLASHROM_ADD_OPT_UPDATE="-N --fmap -i COREBOOT"
      fi
      # If RW_B present, use this variable later to perform 2-step update
      grep -q "RW_SECTION_B" <<< $BINARY_FMAP_LAYOUT && BINARY_HAS_RW_B=0
    fi
  else
    print_warning "Could not read the FMAP region"
    echo "Could not read the FMAP region" >> $ERR_LOG_FILE
  fi
}

set_intel_regions_update_params() {
  if [ $BOARD_HAS_FD_REGION -eq 0 ]; then
    # No FD on board, so no further flashing
    FLASHROM_ADD_OPT_REGIONS=""
  else
    # Safe defaults, only BIOS region and do not verify all regions,
    # as some of them may not be readable. First argument is the initial
    # params.
    FLASHROM_ADD_OPT_REGIONS=$1

    if [ $BINARY_HAS_FD -ne 0 ]; then
      if [ $BOARD_FD_REGION_RW -ne 0 ]; then
        # FD writable and the binary provides FD, safe to flash
        FLASHROM_ADD_OPT_REGIONS+=" -i fd"
      else
        print_error "The firmware binary to be flashed contains Flash Descriptor (FD), but FD is not writable!"
        print_warning "Proceeding without FD flashing, as it is not critical."
        echo "The firmware binary contains Flash Descriptor (FD), but FD is not writable!"  >> $ERR_LOG_FILE
      fi
    fi

    if [ $BINARY_HAS_ME -ne 0 ]; then
      if [ $BOARD_ME_REGION_RW -ne 0 ]; then
        # ME writable and the binary provides ME, safe to flash if ME disabled
        if [ $ME_DISABLED -eq 1 ]; then
          FLASHROM_ADD_OPT_REGIONS+=" -i me"
        else
          echo "The firmware binary to be flashed contains Management Engine (ME), but ME is not disabled!"  >> $ERR_LOG_FILE
          print_error "The firmware binary contains Management Engine (ME), but ME is not disabled!"
          force_me_update
        fi
      else
        echo "The firmware binary to be flashed contains Management Engine (ME), but ME is not writable!"  >> $ERR_LOG_FILE
        print_error "The firmware binary contains Management Engine (ME), but ME is not writable!"
      fi
    fi
  fi
}

handle_fw_switching() {
  local _can_switch_to_heads=$1

  if [ "$_can_switch_to_heads" == "true" ] && [ "$DASHARO_FLAVOR" != "Dasharo (coreboot+heads)" ]; then
    while : ; do
      echo
      read -r -p "Would you like to switch to Dasharo heads firmware? (Y|n) " OPTION
      echo

      case ${OPTION} in
        yes|y|Y|Yes|YES)
          UPDATE_VERSION=$HEADS_REL_VER_DPP
          FLASHROM_ADD_OPT_UPDATE_OVERRIDE=$HEADS_SWITCH_FLASHROM_OPT_OVERRIDE
          BIOS_HASH_LINK="${HEADS_HASH_LINK_DPP}"
          BIOS_SIGN_LINK="${HEADS_SIGN_LINK_DPP}"
          BIOS_LINK="$HEADS_LINK_DPP"

          # Check EC link additionally, not all platforms have Embedded Controllers:
          if [ -n "$EC_LINK_DPP" ]; then
            EC_LINK=$EC_LINK_DPP
            EC_HASH_LINK=$EC_HASH_LINK_DPP
            EC_SIGN_LINK=$EC_SIGN_LINK_DPP
          elif [ -n "$EC_LINK_COMM" ]; then
            EC_LINK=$EC_LINK_COMM
            EC_HASH_LINK=$EC_HASH_LINK_COMM
            EC_SIGN_LINK=$EC_SIGN_LINK_COMM
          fi

          export SWITCHING_TO="heads"
          echo
          echo "Switching to Dasharo heads firmware v$UPDATE_VERSION"
          break
          ;;
        n|N)
          compare_versions $DASHARO_VERSION $UPDATE_VERSION
          if [ $? -ne 1 ]; then
            error_exit "No update available for your machine"
          fi
          echo "Will not install Dasharo heads firmware. Proceeding with regular Dasharo firmware update."
          break
          ;;
        *)
          ;;
      esac
    done
  elif [ -n "$DPP_IS_LOGGED" ] && [ -n "$HEADS_LINK_DPP" ]; then
    local _heads_dpp=1
    curl -sfI -u "$USER_DETAILS" -H "$CLOUD_REQUEST" "$HEADS_LINK_DPP" -o /dev/null
    _heads_dpp=$?
    # We are on heads, offer switch back or perform update if DPP gives access to heads
    if [ "$DASHARO_FLAVOR" == "Dasharo (coreboot+heads)" ]; then
      while : ; do
        echo
        print_warning 'If you are running heads firmware variant and want to update, say "n" here.'
        print_warning 'You will be asked for heads update confirmation in a moment.'
        print_warning 'Say "Y" only if you want to migrate from heads to UEFI firmware variant.'
        read -r -p "Would you like to switch back to the regular (UEFI) Dasharo firmware variant? (Y|n) " OPTION
        echo

        case ${OPTION} in
          yes|y|Y|Yes|YES)
            echo
            echo "Switching back to regular Dasharo firmware v$UPDATE_VERSION"
            echo
            FLASHROM_ADD_OPT_UPDATE_OVERRIDE=$HEADS_SWITCH_FLASHROM_OPT_OVERRIDE
            export SWITCHING_TO="uefi"
            break
            ;;
          n|N)
            if [ $_heads_dpp -ne 0 ]; then
              error_exit "No update available for your machine"
            fi
            UPDATE_VERSION=$HEADS_REL_VER_DPP
            compare_versions $DASHARO_VERSION $UPDATE_VERSION
            if [ $? -ne 1 ]; then
              error_exit "No update available for your machine"
            fi
            echo "Will not switch back to regular Dasharo firmware. Proceeding with Dasharo heads firmware update to $UPDATE_VERSION."
            FLASHROM_ADD_OPT_UPDATE_OVERRIDE="--ifd -i bios"
            BIOS_HASH_LINK="${HEADS_HASH_LINK_DPP}"
            BIOS_SIGN_LINK="${HEADS_SIGN_LINK_DPP}"
            BIOS_LINK="$HEADS_LINK_DPP"

            # Check EC link additionally, not all platforms have Embedded Controllers:
            if [ -n "$EC_LINK_DPP" ]; then
              EC_LINK=$EC_LINK_DPP
              EC_HASH_LINK=$EC_HASH_LINK_DPP
              EC_SIGN_LINK=$EC_SIGN_LINK_DPP
            elif [ -n "$EC_LINK_COMM" ]; then
              EC_LINK=$EC_LINK_COMM
              EC_HASH_LINK=$EC_HASH_LINK_COMM
              EC_SIGN_LINK=$EC_SIGN_LINK_COMM
            fi

            break
            ;;
          *)
            ;;
        esac
      done
    fi
  elif [ -z "$DPP_IS_LOGGED" ] && [ "$DASHARO_FLAVOR" == "Dasharo (coreboot+heads)" ]; then
    # Not logged with DPP and we are on heads, offer switch back
    compare_versions $DASHARO_VERSION $HEADS_REL_VER_DPP
    if [ $? -eq 1 ]; then
      print_warning "You are running heads firmware, but did not provide DPP credentials."
      print_warning "There are updates available if you provide DPP credentials in main DTS menu."
    fi
    echo
    echo "Latest available Dasharo version: $HEADS_REL_VER_DPP"
    echo
    while : ; do
      echo
      read -r -p "Would you like to switch back to the regular Dasharo firmware? (Y|n) " OPTION
      echo

      case ${OPTION} in
        yes|y|Y|Yes|YES)
          echo
          echo "Switching back to regular Dasharo firmware v$UPDATE_VERSION"
          echo
          FLASHROM_ADD_OPT_UPDATE_OVERRIDE=$HEADS_SWITCH_FLASHROM_OPT_OVERRIDE
          export SWITCHING_TO="uefi"
          break
          ;;
        n|N)
          print_warning "No update currently possible. Aborting update process..."
          exit 0
          break;
          ;;
        *)
          ;;
      esac
    done
  else
    compare_versions $DASHARO_VERSION $UPDATE_VERSION
    if [ $? -ne 1 ]; then
      error_exit "No update available for your machine"
    fi
  fi
}

sync_clocks() {
  echo "Waiting for system clock to be synced ..."
  chronyc waitsync 10 0 0 5 >/dev/null 2>>ERR_LOG_FILE
  if [[ $? -ne 0 ]]; then
    print_warning "Failed to sync system clock with NTP server!"
    print_warning "Some time critical tasks might fail!"
  fi
}

print_disclaimer() {
echo -e \
"Please note that the report is not anonymous, but we will use it only for\r
backup and future improvement of the Dasharo product. Every log is encrypted\r
and sent over HTTPS, so security is assured.\r
If you still have doubts, you can skip HCL report generation.\r\n
What is inside the HCL report? We gather information about:\r
  - PCI, Super I/O, GPIO, EC, audio, and Intel configuration,\r
  - MSRs, CMOS NVRAM, CPU info, DIMMs, state of touchpad, SMBIOS and ACPI tables,\r
  - Decoded BIOS information, full firmware image backup, kernel dmesg,\r
  - IO ports, input bus types, and topology - including I2C and USB,\r
\r
You can find more info about HCL in docs.dasharo.com/glossary\r"
}

show_ram_inf() {
  # trace logging is quite slow due to timestamp (calls 'date')
  stop_trace_logging
  # Get the data:
  local data=""
  data=$($DMIDECODE)

  # Initialize an empty array to store the extracted values:
  local -a memory_devices_array

  # Parse the data to exclude fields "Locator" and "Part Number" and format to
  # "Locator: Part Number":
  while IFS= read -r line; do
    # memory_device signals whether the line contains beginning of "Memory
    # Device" dmidecode structure, if so - set to 1 and pars the structure, if
    # the line contains "Handle" (the string every structure in dmidecode begins
    # with) - set to 0:
    if [[ $line =~ ^Handle ]]; then
      memory_device=0
    elif [[ $line =~ Memory\ Device ]]; then
      memory_device=1
    # Modify entry if "Memory Device" structure has been found
    # (memory_device is set to 1) and either "Locator" or "Part Number"
    # fields have been found:
    elif [[ $memory_device -eq 1 && $line =~ Locator:\ |Part\ Number: ]]; then
      # Extract a value of "Locator" field and then add a value of "Part Number"
      # field but ignore "Bank Locator" field, cos it will be included by parent
      # condition:
      if [[ $line =~ Bank\ Locator ]]; then
        continue  # Ignore Bank Locator field.
      elif [[ $line =~ Locator: ]]; then
        entry="${line#*: }"  # Extract the Locator value.
      elif [[ $line =~ Part\ Number: ]]; then
        entry+=": ${NORMAL}${line#*: }"  # Concatenate Part Number value with
					 # Locator and add a colon with yellow
					 # color termination.
        memory_devices_array+=("$entry")
      fi
    fi
  done <<< "$data"

  # Print the extracted values preformatted:
  for entry in "${memory_devices_array[@]}"; do
    echo -e "${BLUE}**${YELLOW}    RAM ${entry}"
  done
  start_trace_logging
}

show_header() {
  local _os_version
  _os_version=$(grep "VERSION_ID" ${OS_VERSION_FILE} | cut -d "=" -f 2-)
  printf "\ec"
  echo -e "${NORMAL}\n Dasharo Tools Suite Script ${_os_version} ${NORMAL}"
  echo -e "${NORMAL} (c) Dasharo <contact@dasharo.com> ${NORMAL}"
  echo -e "${NORMAL} Report issues at: https://github.com/Dasharo/dasharo-issues ${NORMAL}"
}

show_hardsoft_inf() {
  echo -e "${BLUE}*********************************************************${NORMAL}"
  echo -e "${BLUE}**${NORMAL}                HARDWARE INFORMATION ${NORMAL}"
  echo -e "${BLUE}*********************************************************${NORMAL}"
  echo -e "${BLUE}**${YELLOW}    System Inf.: ${NORMAL}${SYSTEM_VENDOR} ${SYSTEM_MODEL}"
  echo -e "${BLUE}**${YELLOW} Baseboard Inf.: ${NORMAL}${SYSTEM_VENDOR} ${BOARD_MODEL}"
  echo -e "${BLUE}**${YELLOW}       CPU Inf.: ${NORMAL}${CPU_VERSION}"
  show_ram_inf
  echo -e "${BLUE}*********************************************************${NORMAL}"
  echo -e "${BLUE}**${NORMAL}                FIRMWARE INFORMATION ${NORMAL}"
  echo -e "${BLUE}*********************************************************${NORMAL}"
  echo -e "${BLUE}**${YELLOW} BIOS Inf.: ${NORMAL}${BIOS_VENDOR} ${BIOS_VERSION}"
  echo -e "${BLUE}*********************************************************${NORMAL}"
}

show_dpp_credentials() {
  if [ -n "${DPP_IS_LOGGED}" ]; then
    echo -e "${BLUE}**${NORMAL}                DPP credentials ${NORMAL}"
    echo -e "${BLUE}*********************************************************${NORMAL}"
    echo -e "${BLUE}**${YELLOW}       Logs key: ${NORMAL}${CLOUDSEND_LOGS_URL}"
    echo -e "${BLUE}**${YELLOW}   Download key: ${NORMAL}${CLOUDSEND_DOWNLOAD_URL}"
    echo -e "${BLUE}**${YELLOW}       Password: ${NORMAL}${CLOUDSEND_PASSWORD}"
    echo -e "${BLUE}*********************************************************${NORMAL}"
  fi
}

show_ssh_info() {
  if systemctl is-active sshd.service &> /dev/null; then
    local ip=""
    ip=$(ip -br -f inet a show scope global | grep UP | awk '{ print $3 }' | tr '\n' ' ')
    # Display "check your connection" in red color in IP field in case no IPV4
    # address is assigned, otherwise display IP/PORT:
    if [[ -z "$ip" ]]; then
      echo -e "${BLUE}**${NORMAL}    SSH status: ${GREEN}ON${NORMAL} IP: ${RED}check your connection${NORMAL}"
      echo -e "${BLUE}*********************************************************${NORMAL}"
    else
      echo -e "${BLUE}**${NORMAL}    SSH status: ${GREEN}ON${NORMAL} IP: ${ip}${NORMAL}"
      echo -e "${BLUE}*********************************************************${NORMAL}"
    fi
  fi
}

show_main_menu() {
  echo -e "${BLUE}**${YELLOW}     ${HCL_REPORT_OPT})${BLUE} Dasharo HCL report${NORMAL}"
  if check_if_dasharo; then
    echo -e "${BLUE}**${YELLOW}     ${DASHARO_FIRM_OPT})${BLUE} Update Dasharo Firmware${NORMAL}"
  # flashrom does not support QEMU. TODO: this could be handled in a better way:
  elif [ "${SYSTEM_VENDOR}" != "QEMU" ] && [ "${SYSTEM_VENDOR}" != "Emulation" ]; then
    echo -e "${BLUE}**${YELLOW}     ${DASHARO_FIRM_OPT})${BLUE} Install Dasharo Firmware${NORMAL}"
  fi
  # flashrom does not support QEMU. TODO: this could be handled in a better way:
  if [ "${SYSTEM_VENDOR}" != "QEMU" ] && [ "${SYSTEM_VENDOR}" != "Emulation" ]; then
    echo -e "${BLUE}**${YELLOW}     ${REST_FIRM_OPT})${BLUE} Restore firmware from Dasharo HCL report${NORMAL}"
  fi
  if [ -n "${DPP_IS_LOGGED}" ]; then
    echo -e "${BLUE}**${YELLOW}     ${DPP_KEYS_OPT})${BLUE} Edit your DPP keys${NORMAL}"
  else
    echo -e "${BLUE}**${YELLOW}     ${DPP_KEYS_OPT})${BLUE} Load your DPP keys${NORMAL}"
  fi
  if [ -f "${DPP_SUBMENU_JSON}" ]; then
    echo -e "${BLUE}**${YELLOW}     ${DPP_SUBMENU_OPT})${BLUE} DTS extensions${NORMAL}"
  fi
}

main_menu_options(){
  local OPTION=$1

  case ${OPTION} in
    "${HCL_REPORT_OPT}")
      print_disclaimer
      read -p "Do you want to support Dasharo development by sending us logs with your hardware configuration? [N/y] "
      case ${REPLY} in
          yes|y|Y|Yes|YES)
          export SEND_LOGS="true"
          echo "Thank you for contributing to the Dasharo development!"
          ;;
          *)
          export SEND_LOGS="false"
          echo "Logs will be saved in root directory."
          echo "Please consider supporting Dasharo by sending the logs next time."
          ;;
      esac
      if [ "${SEND_LOGS}" == "true" ]; then
          # DEPLOY_REPORT variable is used in dasharo-hcl-report to determine
          # which logs should be printed in the terminal, in the future whole
          # dts scripting should get some LOGLEVEL and maybe dumping working
          # logs to file
          export DEPLOY_REPORT="false"
          wait_for_network_connection && ${CMD_DASHARO_HCL_REPORT} && LOGS_SENT="1"
      else
          export DEPLOY_REPORT="false"
          ${CMD_DASHARO_HCL_REPORT}
      fi
      read -p "Press Enter to continue."

      return 0
      ;;
    "${DASHARO_FIRM_OPT}")
      if ! check_if_dasharo; then
        # flashrom does not support QEMU, but installation depends on flashrom.
        # TODO: this could be handled in a better way:
        [ "${SYSTEM_VENDOR}" = "QEMU" ] || [ "${SYSTEM_VENDOR}" = "Emulation" ] && return 0

        if wait_for_network_connection; then
          echo "Preparing ..."
          if [ -z "${LOGS_SENT}" ]; then
            export SEND_LOGS="true"
            export DEPLOY_REPORT="true"
            if ! ${CMD_DASHARO_HCL_REPORT}; then
              echo -e "Unable to connect to cloud.3mdeb.com for submitting the
                        \rHCL report. Please recheck your internet connection."
            else
              LOGS_SENT="1"
            fi
          fi
        fi

        if [ -n "${LOGS_SENT}" ]; then
          if ! ${CMD_DASHARO_DEPLOY} install; then
            send_dts_logs
          fi
        fi
      else
        # TODO: This should be placed in dasharo-deploy:
        # For NovaCustom TGL laptops with Dasharo version lower than 1.3.0,
        # we shall run the ec_transition script instead. See:
        # https://docs.dasharo.com/variants/novacustom_nv4x_tgl/releases/#v130-2022-10-18
        if [ "$SYSTEM_VENDOR" = "Notebook" ]; then
            case "$SYSTEM_MODEL" in
              "NS50_70MU"|"NV4XMB,ME,MZ")
                compare_versions $DASHARO_VERSION 1.3.0
                if [ $? -eq 1 ]; then
                # For Dasharo version lesser than 1.3.0
                  print_warning "Detected NovaCustom hardware with version < 1.3.0"
                  print_warning "Need to perform EC transition after which the platform will turn off"
                  print_warning "Then, please power it on and proceed with update again"
                  print_warning "EC transition procedure will start in 5 seconds"
                  sleep 5
                  ${CMD_EC_TRANSITION}
                  error_check "Could not perform EC transition"
                fi
                # Continue with regular update process for Dasharo version
                #  greater or equal 1.3.0
                ;;
            esac
        fi

        # Use regular update process for everything else
        if ! ${CMD_DASHARO_DEPLOY} update; then
          send_dts_logs
        fi
      fi
      read -p "Press Enter to continue."

      return 0
      ;;
    "${REST_FIRM_OPT}")
      # flashrom does not support QEMU, but restore depends on flashrom.
      # TODO: this could be handled in a better way:
      [ "${SYSTEM_VENDOR}" = "QEMU" ] || [ "${SYSTEM_VENDOR}" = "Emulation" ] && return 0

      if check_if_dasharo; then
        if ! ${CMD_DASHARO_DEPLOY} restore; then
          send_dts_logs
        fi
      fi
      read -p "Press Enter to continue."

      return 0
      ;;
    "${DPP_KEYS_OPT}")
      local _result
      # Return if there was an issue when asking for credentials:
      if ! get_dpp_creds; then
        read -p "Press Enter to continue."
        return 0
      fi


      # Check for Dasharo Firmware for the current platform, continue to
      # packages after checking:
      check_for_dasharo_firmware
      _result=$?

      echo "Your credentials give access to:"
      echo -n "Dasharo Pro Package (DPP): "

      if [ $_result -eq 0 ]; then
        # FIXME: what if credentials have access to
        # firmware, but check_for_dasharo_firmware will not detect any platform?
        # According to check_for_dasharo_firmware it will return 1 in both
        # cases which means that we cannot detect such case.
        print_ok "YES"
      else
        echo "NO"
      fi

      echo -n "DTS Extensions: "

      # Try to log in using available DPP credentials, start loop over if login
      # was not successful:
      login_to_dpp_server
      if [ $? -ne 0 ]; then
        echo "NO"
	read -p "Press Enter to continue"
        return 0
      fi

      print_ok "YES"

      # Check if there is some packages available to install, start loop over if
      # no packages is available:
      check_avail_dpp_packages || return 0

      # Download and install available packages, start loop over if there is
      # no packages to install:
      install_all_dpp_packages || return 0

      # Parse installed packages for premium submenus:
      parse_for_premium_submenu

      read -p "Press Enter to continue."
      return 0
      ;;
    "${DPP_SUBMENU_OPT}")
      [ -f "$DPP_SUBMENU_JSON" ] || return 0
      export DPP_SUBMENU_ACTIVE="true"
      return 0
      ;;
  esac

  return 1
}

show_footer(){
  echo -e "${BLUE}*********************************************************${NORMAL}"
  echo -ne "${RED}${REBOOT_OPT_UP}${NORMAL} to reboot  ${NORMAL}"
  echo -ne "${RED}${POWEROFF_OPT_UP}${NORMAL} to poweroff  ${NORMAL}"
  echo -e "${RED}${SHELL_OPT_UP}${NORMAL} to enter shell  ${NORMAL}"
  if systemctl is-active sshd.service &> /dev/null; then
    echo -ne "${RED}${SSH_OPT_UP}${NORMAL} to stop SSH server  ${NORMAL}"
  else
    echo -ne "${RED}${SSH_OPT_UP}${NORMAL} to launch SSH server  ${NORMAL}"
  fi
  if [ "${SEND_LOGS_ACTIVE}" == "true" ]; then
    echo -e "${RED}${SEND_LOGS_OPT}${NORMAL} to disable sending DTS logs ${NORMAL}"
  else
    echo -e "${RED}${SEND_LOGS_OPT}${NORMAL} to enable sending DTS logs ${NORMAL}"
  fi
  echo -ne "${YELLOW}\nEnter an option:${NORMAL}"
}

footer_options(){
  local OPTION=$1

  case ${OPTION} in
    "${SSH_OPT_UP}" | "${SSH_OPT_LOW}")
      wait_for_network_connection || return 0

      if systemctl is-active sshd.service> /dev/null 2>&1; then
        print_ok "Turning off the SSH server..."
        systemctl stop sshd.service
      else
        print_warning "Starting SSH server!"
        print_warning "Now you can log in into the system using root account."
        print_warning "Stopping server will not drop all connected sessions."
        systemctl start sshd.service
        print_ok "Listening on IPs: $(ip -br -f inet a show scope global | grep UP | awk '{ print $3 }' | tr '\n' ' ')"
      fi
      read -p "Press Enter to continue."

      return 0
      ;;
    "${SHELL_OPT_UP}" | "${SHELL_OPT_LOW}")
      clear
      echo "Entering shell, to leave type exit and press Enter or press LCtrl+D"
      echo ""
      send_dts_logs
      stop_logging
      ${CMD_SHELL}
      start_logging

      # If in submenu before going to shell - return to main menu after exiting
      # shell:
      unset DPP_SUBMENU_ACTIVE
      ;;
    "${POWEROFF_OPT_UP}" | "${POWEROFF_OPT_LOW}")
      send_dts_logs
      ${POWEROFF}
      ;;
    "${REBOOT_OPT_UP}" | "${REBOOT_OPT_LOW}")
      send_dts_logs
      ${REBOOT}
      ;;
    "${SEND_LOGS_OPT}" | "${SEND_LOGS_OPT_LOW}")
      if [ "${SEND_LOGS_ACTIVE}" == "true" ]; then
        unset SEND_LOGS_ACTIVE
      else
        export SEND_LOGS_ACTIVE="true"
      fi
      ;;
  esac

  return 1
}

send_dts_logs(){
  if [ "${SEND_LOGS_ACTIVE}" == "true" ]; then
    echo "Sending logs..."

    log_dir=$(dmidecode -s system-manufacturer)_$(dmidecode -s system-product-name)_$(dmidecode -s bios-version)

    uuid_string="$(cat /sys/class/net/"$(ip route show default | head -1 | awk '/default/ {print $5}')"/address)"
    uuid_string+="_$(dmidecode -s system-product-name)"
    uuid_string+="_$(dmidecode -s system-manufacturer)"

    uuid=`uuidgen -n @x500 -N $uuid_string -s`

    log_dir+="_${uuid}_$(date +'%Y_%m_%d_%H_%M_%S_%N')"
    log_dir="${log_dir// /_}"
    log_dir="${log_dir//\//_}"
    log_dir="/tmp/${log_dir}"

    mkdir $log_dir
    cp ${DTS_LOG_FILE} $log_dir
    cp ${DTS_VERBOSE_LOG_FILE} $log_dir

    if [ -f ${ERR_LOG_FILE_REALPATH} ]; then
      cp ${ERR_LOG_FILE_REALPATH} $log_dir
    fi

    if [ -f ${FLASHROM_LOG_FILE} ]; then
      cp ${FLASHROM_LOG_FILE} $log_dir
    fi
    tar czf "${log_dir}.tar.gz" $log_dir

    FULL_DTS_URL="https://cloud.3mdeb.com/index.php/s/"${BASE_DTS_LOGS_URL}

    CLOUDSEND_PASSWORD=${DTS_LOGS_PASSWORD} cloudsend.sh \
      "-e" \
      "${log_dir}.tar.gz" \
      "${FULL_DTS_URL}"

    if [ "$?" -ne "0" ]; then
      echo "Failed to send logs to the cloud"
      return 1
    fi
    unset SEND_LOGS_ACTIVE
  fi
}

check_if_fused() {
  local _file_path
  _file_path="/sys/class/mei/mei0/fw_status"
  local _file_content
  local _hfsts6_value
  local _line_number
  local _hfsts6_binary
  local _binary_length
  local _padding
  local _zeros
  local _bit_30_value

  if ! $FSREAD_TOOL test -f "$_file_path"; then
    print_error "File not found: $_file_path"
    return 2
  fi

  _file_content="$($FSREAD_TOOL cat $_file_path)"

  _fsts6_value=""
  _line_number=1
  while IFS= read -r line; do
    if [[ $_line_number -eq 6 ]]; then
      _hfsts6_value="$line"
      break
    fi
    ((_line_number++))
  done <<< "$_file_content"

  if [[ -z "$_hfsts6_value" ]]; then
    print_error "Failed to read HFSTS6 value"
    exit 1
  fi

  _hfsts6_binary=$(echo "ibase=16; obase=2; $_hfsts6_value" | bc)
  _binary_length=${#_hfsts6_binary}

  # Add leading zeros
  if [ $_binary_length -lt 32 ]; then
    _padding=$((32 - $_binary_length))
    _zeros=$(printf "%${_padding}s" | tr ' ' "0")
    _hfsts6_binary=$_zeros$_hfsts6_binary
  fi

  _bit_30_value=${_hfsts6_binary:1:1}

  if [ $_bit_30_value == 0 ]; then
    return 1
  else
    return 0
  fi
}

check_if_boot_guard_enabled() {
  local _msr_hex
  local _msr_binary
  local _binary_length
  local _padding
  local _zeros
  local _facb_fpf
  local _verified_boot

  # MSR cannot be read
  if ! $RDMSR boot_guard_status_mock 0x13a -0; then
    return 1
  fi

  _msr_hex=$($RDMSR boot_guard_status_mock 0x13a -0 | tr '[:lower:]' '[:upper:]')
  _msr_binary=$(echo "ibase=16; obase=2; $_msr_hex" | bc)

  _binary_length=${#_msr_binary}
arkuszu
  if [ $_binary_length -lt 64 ]; then
    _padding=$((64 - $_binary_length))
    _zeros=$(printf "%${_padding}s" | tr ' ' "0")
    _msr_binary=$_zeros$_msr_binary
  fi

  # Bit 4
  _facb_fpf=${_msr_binary:59:1}

  # Bit 6
  _verified_boot=${_msr_binary:57:1}

  if [ $_facb_fpf == 1 ] && [ $_verified_boot == 1 ]; then
    return 0
  fi
  return 1
}

can_install_dasharo() {
  if check_if_intel; then
    if check_if_fused && check_if_boot_guard_enabled; then
      return 1
    fi
  fi
  return 0
}

check_if_intel() {
  cpu_vendor=$(cat /proc/cpuinfo | grep "vendor_id" | head -n 1 | sed 's/.*: //')
  if [ $cpu_vendor == "GenuineIntel" ]; then
    return 0
  fi
}
