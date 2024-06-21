#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2024 3mdeb <contact@3mdeb.com>
#
# SPDX-License-Identifier: Apache-2.0

# shellcheck disable=SC2034
# shellcheck source=../include/dts-environment.sh
source $DTS_ENV

check_des_creds() {
  echo "Verifying Dasharo DES credentials..."

  local _check_dwn_req_resp_uefi="0"
  local _check_dwn_req_resp_heads="0"
  local _check_logs_req_resp="0"
  # Ignore "SC2154 (warning): SE_credential_file is referenced but not assigned"
  # for external variable:
  # shellcheck disable=SC2154
  CLOUDSEND_LOGS_URL=$(sed -n '1p' < ${SE_credential_file} | tr -d '\n')
  CLOUDSEND_DOWNLOAD_URL=$(sed -n '2p' < ${SE_credential_file} | tr -d '\n')
  CLOUDSEND_PASSWORD=$(sed -n '3p' < ${SE_credential_file} | tr -d '\n')
  USER_DETAILS="$CLOUDSEND_DOWNLOAD_URL:$CLOUDSEND_PASSWORD"
  board_config
  if [ "$?" == "1" ]; then
    return 1
  fi
  TEST_LOGS_URL="https://cloud.3mdeb.com/index.php/s/${CLOUDSEND_LOGS_URL}/authenticate/showShare"

  if [ ! -v BIOS_LINK_DES ] && [ ! -v HEADS_LINK_DES ]; then
    print_error "There is no Dasharo Entry Subscription available for your platform!"
    return 1
  fi

  if wait_for_network_connection; then
    if [ -v BIOS_LINK_DES ]; then
      _check_dwn_req_resp_uefi=$(curl -L -I -s -f -u "$USER_DETAILS" -H "$CLOUD_REQUEST" "$BIOS_LINK_DES" -o /dev/null -w "%{http_code}")
    fi
    if [ -v HEADS_LINK_DES ]; then
      _check_dwn_req_resp_heads=$(curl -L -I -s -f -u "$USER_DETAILS" -H "$CLOUD_REQUEST" "$HEADS_LINK_DES" -o /dev/null -w "%{http_code}")
    fi

    _check_logs_req_resp=$(curl -L -I -s -f -H "$CLOUD_REQUEST" "$TEST_LOGS_URL" -o /dev/null -w "%{http_code}")
    if [ ${_check_dwn_req_resp_uefi} -eq 200 ] || [ ${_check_dwn_req_resp_heads} -eq 200 ]; then
      if [ ${_check_logs_req_resp} -eq 200 ]; then
        print_ok "Verification of the Dasharo DES was successful. They are valid and will be used."
        return 0
      fi
    fi
  fi

  print_error "Something may be wrong with the DES credentials. Please use option 4 to change the DES keys
           \rand make sure that there is no typo."
  rm ${SE_credential_file}
  export CLOUDSEND_LOGS_URL="$BASE_CLOUDSEND_LOGS_URL"
  export CLOUDSEND_PASSWORD="$BASE_CLOUDSEND_PASSWORD"
  unset CLOUDSEND_DOWNLOAD_URL
  unset DES_IS_LOGGED
  read -p "Press ENTER to continue"
  return 1
}

get_des_creds() {
  echo ""
  read -p "Enter logs key:                " 'TMP_CLOUDSEND_LOGS_URL'
  echo ""
  read -p "Enter firmware download key:   " 'TMP_CLOUDSEND_DOWNLOAD_URL'
  echo ""
  read -p "Enter password:                " 'TMP_CLOUDSEND_PASSWORD'

  # Export DPP creds to a file for future use. Currently these are being used
  # for both: MinIO (and its mc CLI) and cloudsend (deprecated, all DPP
  # sibscribtions will be megrated to MinIO):
  echo ${TMP_CLOUDSEND_LOGS_URL} > ${SE_credential_file}
  echo ${TMP_CLOUDSEND_DOWNLOAD_URL} >> ${SE_credential_file}
  echo ${TMP_CLOUDSEND_PASSWORD} >> ${SE_credential_file}

  print_ok "Dasharo DES credentials have been saved"
}

login_to_des_server(){
  # Check if the user is already logged in, log in if not:
  if [ -z "$(mc alias list | grep ${CLOUDSEND_DOWNLOAD_URL})" ]; then
    mc alias set $DES_SERVER_USER_ALIAS $DES_SERVER_ADDRESS $CLOUDSEND_DOWNLOAD_URL $CLOUDSEND_PASSWORD || return 1
    if [ $? -ne 0 ]; then
      print_error "Error while logging in to DES server!"
      return 1
    fi
  fi

  return 0
}

subscription_routine(){
  # This function contains Subscription-related code which needs to be executed
  # several times. Currently it is called only in /usr/sbin/dts script at every
  # start of menu rendering loop.
  #
  # Currently it does the following:
  # Managing DPP creds., so the loop will detect them;
  # Connects to DPP server.
  export CLOUDSEND_LOGS_URL
  export CLOUDSEND_DOWNLOAD_URL
  export CLOUDSEND_PASSWORD

  # Each time the main menu is rendered, check for DES credentials and export
  # them, if file exists
  if [ -e "${SE_credential_file}" ]; then
    CLOUDSEND_LOGS_URL=$(sed -n '1p' < ${SE_credential_file} | tr -d '\n')
    CLOUDSEND_DOWNLOAD_URL=$(sed -n '2p' < ${SE_credential_file} | tr -d '\n')
    CLOUDSEND_PASSWORD=$(sed -n '3p' < ${SE_credential_file} | tr -d '\n')
    export USER_DETAILS="$CLOUDSEND_DOWNLOAD_URL:$CLOUDSEND_PASSWORD"
    export DES_IS_LOGGED="true"
  else
    CLOUDSEND_LOGS_URL="$BASE_CLOUDSEND_LOGS_URL"
    CLOUDSEND_PASSWORD="$BASE_CLOUDSEND_PASSWORD"
    unset CLOUDSEND_DOWNLOAD_URL
    unset DES_IS_LOGGED
    return 1
  fi

  # Network connection may not be available on boot, do not connect if so:
  check_network_connection && login_to_des_server || return 0

  return 0
}

check_dasharo_package_env(){
  [ -d $DES_PACKAGE_MANAGER_DIR ] || mkdir -p $DES_PACKAGE_MANAGER_DIR

  return 0
}

update_package_list(){
  check_dasharo_package_env

  mc find --json --name "*.rpm" $DES_SERVER_USER_ALIAS > $DES_AVAIL_PACKAGES_LIST

  if [ $? -ne 0 ]; then
    print_error "Unable to get package list!"
    return 1
  fi
  return 0
}

download_des_package(){
  local package_name=$1

  # Make sure all paths exist:
  check_dasharo_package_env

  echo "Downloading package $package_name..."

  # Get package link:
  local download_link
  download_link=$(jq -r '.key' "$DES_AVAIL_PACKAGES_LIST" | grep "$package_name")

  if [ -z "$download_link" ]; then
    print_error "No package $package_name found!"
    return 1
  fi

  # TODO: this will overwrite file with name package_name if its exists, a place
  # for improvements:
  local local_path="$DES_PACKAGE_MANAGER_DIR/$package_name"
  mc get --quiet "$download_link" "$local_path"

  [ $? -ne 0 ] && return 1

  print_ok "Package $package_name have been downloaded successfully!"
  return 0
}

install_des_package(){
  local package_name=$1

  echo "Installing package $package_name..."

  update_package_list || return 1

  if [ ! -f "$DES_PACKAGE_MANAGER_DIR/$package_name" ]; then
    download_des_package $package_name || return 1
  fi

  rpm -ivh $DES_PACKAGE_MANAGER_DIR/$package_name

  if [ $? -ne 0 ]; then
    rm -f $DES_PACKAGE_MANAGER_DIR/$package_name
    print_error "Could not install package $package_name!"
    return 1
  fi

  rm -f $DES_PACKAGE_MANAGER_DIR/$package_name

  print_ok "Package $package_name have been installed successfully!"
  return 0
}

install_all_des_packages(){
  echo "Installing available DES packages..."

  update_package_list || return 1

  # Strip out exact packages download links from the .json data:
  local packages_to_download
  packages_to_download=$(jq -r '.key' "$DES_AVAIL_PACKAGES_LIST")

  echo "$packages_to_download" | while read -r download_link; do
    # Define the local file path:
    local package_name
    package_name=$(basename "$download_link")

    install_des_package $package_name
  done

  return 0
}

check_avail_des_packages(){
  echo "Checking for available DES packages..."
  AVAILABLE_PACKAGES=$(mc find --name "*.rpm" $DES_SERVER_USER_ALIAS)

  if [ -z "$AVAILABLE_PACKAGES" ]; then
    return 1
  fi

  return 0
}
