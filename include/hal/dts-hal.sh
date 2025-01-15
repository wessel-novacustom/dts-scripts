#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2024 3mdeb <contact@3mdeb.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# This is a Hardware Abstraction Layer for DTS. The goal of this layer -
# separate all hardware-related code from DTS code to improve readability,
# scalability and testing.
#
# For testing, every hardware-specific tool must utilize DTS_TESTING
# variable, which is declared in dts-environment and set by user. If DTS_TESTING
# is not "true" - HAL communicates with hardware and firmware via specific tools
# otherwise it uses mocking functions and tool_wrapper to emulate behaviour of
# some of the tools.
#
# Real HAL is placed in $DTS_HAL* (* means that, apart from common HAL funcs.
# there could be, in future, files with platform-specific HAL funcs) and the
# Tests HAL is placed in $DTS_MOCK* (* means that, apart from common mocks,
# there could be, in future, files with platform-specific mocking functions).

# shellcheck disable=SC2034

# shellcheck source=../../include/hal/common-mock-func.sh
source $DTS_MOCK_COMMON

# Set tools wrappers:
DASHARO_ECTOOL="tool_wrapper dasharo_ectool"
FLASHROM="tool_wrapper flashrom"
DMIDECODE="tool_wrapper dmidecode"
IFDTOOL="tool_wrapper ifdtool"
SETPCI="tool_wrapper setpci"
# Emulating to eliminate false negatives, because it might fail on QEMU:
CBMEM="tool_wrapper cbmem"
CBFSTOOL="tool_wrapper cbfstool"
# Emulating to eliminate false negatives, because it fails on QEMU:
SUPERIOTOOL="tool_wrapper superiotool"
# Emulating to eliminate false negatives, because it fails on QEMU:
ECTOOL="tool_wrapper ectool"
# Emulating to eliminate false negatives, because it fails on QEMU:
MSRTOOL="tool_wrapper msrtool"
# Emulating to eliminate false negatives, because it fails on QEMU:
MEI_AMT_CHECK="tool_wrapper mei-amt-check"
# Emulating to eliminate false negatives, because it fails on QEMU:
INTELMETOOL="tool_wrapper intelmetool"
# Emulating, so no to probe every time testing is done
HW_PROBE="tool_wrapper hw-probe"
DMESG="tool_wrapper dmesg"
DCU="tool_wrapper dcu"
FUTILITY="tool_wrapper futility"
IOTOOLS="tool_wrapper iotools"
FSREAD_TOOL="tool_wrapper fsread_tool"
CAP_UPD_TOOL="tool_wrapper cap_upd_tool"
LSCPU="tool_wrapper lscpu"
# System commands:
POWEROFF="tool_wrapper poweroff"
REBOOT="tool_wrapper reboot"
RDMSR="tool_wrapper rdmsr"

################################################################################
# Tools wrapper.
################################################################################
tool_wrapper(){
# Usage: tool_wrapper TOOL_NAME MOCK_FUNC_NAME TOOL_ARGS
#
#    TOOL_NAME: the name of the tool being wrapped
#    MOCK_FUNC_NAME: the name of mocking function (optional, check comments
#    below for more inf.)
#    TOOL_ARGS: the arguments that the tool gets if being called, for example
#    for dmidecode -s system-vendor it will be "-s system-vendor".
#
# This function is a bridge between common DTS logic and hardware-specific DTS
# logic or functions. There is two paths a call to this function can be
# redirected to: real HAL for running on real platform and Tests HAL for testing
# on QEMU (depends on whether the var. DTS_TESTING is set or not).
#
# The real HAL are the real tools e.g. cbfstool, etc.. The testing HAL are the
# mocking functions. There are several types of mocking functions, with every
# type having a specific name syntax:
#
# FUNCTIONNAME_mock(){...}: mocking functions specific for every platform, those
# are stored in $DTS_MOCK_PLATFORM file which is sourced at the beginning of
# this file.
# TOOLNAME_FUNCTIONNAME_mock(){...}: mocking functions common for all platforms
# but specific for some tool, those are stored in $DTS_MOCK_COMMON file, which
# is being sourced at the beginning of this file.
# TOOLNAME_common_mock(){...}: standard mocking functions for every tool that
# are common for all platforms, those are stored in $DTS_MOCK_COMMON file, which
# is being sourced at the beginning of this file.
# common_mock(){...}: common mocking function, in case we need to use mocking
# function for a tool but we do not care about its output.
#
# This tool wrapper should only be used with tools which communicate with
# hardware or firmware (read or write, etc.).
#
# TODO: this wrapper deals with arguments as well as with stdout, stderr, and $?
# redirection, but it does not read and redirect stdin (this is not used in any
# mocking functions or tools right now).
  # Gets toolname, e.g. poweroff, dmidecode. etc.:
  local _tool="$1"
  # Gets mocking function name:
  local _mock_func="$2"
  # It checks if _mock_func contains smth with _mock at the end, if not -
  # mocking function is not provided and some common mocking func. will be used
  # instead:
  if ! echo "$_mock_func" | grep "_mock" &> /dev/null; then
    unset _mock_func
    shift 1
  else
    shift 2
  fi
  # Other arguments for this function are the arguments which are sent to a tool
  # e.g. -s system-vendor for dmidecode, etc.:
  local _arguments=( "$@" )

  if [ -n "$DTS_TESTING" ]; then
    # This is the order of calling mocking functions:
    # 1) FUNCTIONNAME_mock;
    # 2) TOOLNAME_FUNCTIONNAME_mock;
    # 3) TOOLNAME_common_mock;
    # 4) common_mock - last resort.
    if [ -n "$_mock_func" ] && type $_mock_func &> /dev/null; then
      $_mock_func "${_arguments[@]}"
    elif type ${_tool}_${_mock_func} &> /dev/null; then
      ${_tool}_${_mock_func} "${_arguments[@]}"
    elif type ${_tool}_common_mock &> /dev/null; then
      ${_tool}_common_mock "${_arguments[@]}"
    else
      common_mock $_tool
    fi

    return $?
  fi

  # If not testing - call tool with the arguments instead:
  $_tool "${_arguments[@]}"

  return $?
}

################################################################################
# Other funcs.
################################################################################
check_for_opensource_firmware()
{
  echo "Checking for Open Source Embedded Controller firmware..."
  $DASHARO_ECTOOL check_for_opensource_firm_mock info > /dev/null 2>>"$ERR_LOG_FILE"

  return $?
}

fsread_tool(){
# This func is an abstraction for proper handling of fs hardware-specific (e.g.
# checking devtmpfs, or sysfs, or some other fs that changes its state due to
# changes in hardware and/or firmware) reads by tool_wrapper.
#
# This function does not have arguments in common understanding, it takes a
# command, that is reading smth from some fs, and its arguments as an only
# argument. E.g. if you want to check tty1 device presence:
#
# fsread_tool test -f /dev/tty1
  local _command="$1"
  shift

  $_command "$@"

  return $?
}

cap_upd_tool(){
# This func is an abstraction for proper handling of UEFI Capsule Update driver
# writing by the tool_wrapper. arguments: capsule update file path, e.g.:
#
# capsule_update_tool /tmp/firm.cap
  local _capsule="$1"

  cat "$_capsule" > "$CAP_UPD_DEVICE"

  return $?
}

check_if_heci_present(){
# FIXME: what if HECI is not device 16.0?
  $FSREAD_TOOL test -d /sys/class/pci_bus/0000:00/device/0000:00:16.0

  return $?
}

check_me_op_mode(){
# Checks ME Current Operation Mode at offset 0x40 bits 19:16:
  local _mode

  _mode="$($SETPCI check_me_op_mode_mock -s 00:16.0 42.B 2>>"$ERR_LOG_FILE" | cut -c2-)"

  echo "$_mode"

  return 0
}
