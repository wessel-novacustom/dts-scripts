#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2024 3mdeb <contact@3mdeb.com>
#
# SPDX-License-Identifier: Apache-2.0

# shellcheck disable=SC2034
# shellcheck source=../include/dts-environment.sh
source $DTS_ENV

check_for_dasharo_firmware() {
  # This function checks if Dasharo firmware is available for the current
  # platform, returns 1 if there is no firmware available, returns 0 otherwise.

  echo "Checking for Dasharo firmware..."

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

  # Check the board information:
  board_config

  # Create links for logs to be sent to:
  TEST_LOGS_URL="https://cloud.3mdeb.com/index.php/s/${CLOUDSEND_LOGS_URL}/authenticate/showShare"

  # If board_config function has not set firmware links - exit with warning:
  if [ ! -v BIOS_LINK_DES ] && [ ! -v HEADS_LINK_DES ]; then
    print_warning "There is no Dasharo Firmware available for your platform."
    return 1
  fi

  # Check for firmware binaries:
  if wait_for_network_connection; then
    if [ -v BIOS_LINK_DES ]; then
      _check_dwn_req_resp_uefi=$(curl -L -I -s -f -u "$USER_DETAILS" -H "$CLOUD_REQUEST" "$BIOS_LINK_DES" -o /dev/null -w "%{http_code}")
    fi
    if [ -v HEADS_LINK_DES ]; then
      _check_dwn_req_resp_heads=$(curl -L -I -s -f -u "$USER_DETAILS" -H "$CLOUD_REQUEST" "$HEADS_LINK_DES" -o /dev/null -w "%{http_code}")
    fi

    _check_logs_req_resp=$(curl -L -I -s -f -H "$CLOUD_REQUEST" "$TEST_LOGS_URL" -o /dev/null -w "%{http_code}")

    # Return 0 if any of Dasharo Firmware binaries is available:
    if [ ${_check_dwn_req_resp_uefi} -eq 200 ] || [ ${_check_dwn_req_resp_heads} -eq 200 ]; then
      if [ ${_check_logs_req_resp} -eq 200 ]; then
        print_ok "A Dasharo Firmware binary has been found for your platform!"
        return 0
      fi
    fi
  fi

  print_warning "Something may be wrong with the DES credentials or you may not\n
		have access to Dasharo Firmware. If so, consider getting Dasharo\n
		Entry Subscription and improving security of your platform!"

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
  [ -d $DES_PACKAGES_SCRIPTS_PATH ] || mkdir -p $DES_PACKAGES_SCRIPTS_PATH

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

  check_dasharo_package_env

  echo "Installing package $package_name..."

  update_package_list || return 1

  if [ ! -f "$DES_PACKAGE_MANAGER_DIR/$package_name" ]; then
    download_des_package $package_name || return 1
  fi

  dnf --assumeyes install $DES_PACKAGE_MANAGER_DIR/$package_name

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

  if [ -z "$packages_to_download" ]; then
    echo "No packages to install."
    return 1
  fi

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

parse_for_premium_submenu() {
  [ -d $DES_PACKAGES_SCRIPTS_PATH ] || return 0

  # Check if the JSON file exists, delete if so. The reason for it is that three
  # operations can be performed on this file: add new script inf., delete a
  # script inf., and update already existing script inf.. By deleting the
  # existing inf. and reparsing - three operations can be replaced with one:
  # deleting and updating - there is no need to delete or update if its being
  # recreated every time.
  [ -f "$DES_SUBMENU_JSON" ] && rm -f "$DES_SUBMENU_JSON"

  # submenu's options start from position 0:
  local position="1"
  local json_data='[]'

  # Iterate over bash scripts in the directory:
  for script in "$DES_PACKAGES_SCRIPTS_PATH"/*; do
    # Skip if not a script:
    [ -n "$(file $script | grep 'script, ASCII text executable')" ] || continue

    # Create the JSON file only if any script have been found, this will be a
    # signal to render premium submenu:
    [ -f "$DES_SUBMENU_JSON" ] || echo '[]' > "$DES_SUBMENU_JSON"

    local script_name
    script_name=$(basename "$script")

    # Add a new entry to the JSON file
    json_data=$(jq --arg name "$script_name" --argjson pos "$position" \
      '. += [{"file_name": $name, "file_menu_position": $pos}]' <<< "$json_data")

    # Increment highest position for next script
    position=$((position + 1))
  done

  # Save updated JSON data
  [ -f "$DES_SUBMENU_JSON" ] && echo "$json_data" | jq '.' > "$DES_SUBMENU_JSON"

  return 0
}

show_des_submenu(){
  # This menu is being rendered dynamically by parsing scripts from
  # DES_PACKAGES_SCRIPTS_PATH. These scripts are being installed by DES
  # packages.
  #
  # Every script should contain menu_point function which should utilize one
  # argument. The argument is a menu position (an integer from zero to infinity;
  # represented by file_menu_position in the JSON file) which signal a position
  # in graphical submenu.

  echo -e "${BLUE}*********************************************************${NORMAL}"

  local file_menu_position

  # Read JSON data:
  local json_data
  json_data=$(jq -c '.[]' "$DES_SUBMENU_JSON")

  # Iterate over each JSON object:
  while IFS= read -r item; do
    local script_name
    script_name=$(jq -r '.file_name' <<< "$item")
    file_menu_position=$(jq -r '.file_menu_position' <<< "$item")

    local script_path="$DES_PACKAGES_SCRIPTS_PATH/$script_name"

    bash "$script_path" menu_point "$file_menu_position"

  done <<< "$json_data"

  echo -e "${BLUE}**${YELLOW}     ${BACK_TO_MAIN_MENU_UP})${BLUE} Return to main menu${NORMAL}"

  return 0
}

des_submenu_options(){
  local OPTION=$1
  local file_menu_position
  local script

  # Do not check JSON file if alphabetical option have been provided to not to
  # cause jq error:
  if [[ "$OPTION" =~ ^[0-9]+$ ]]; then
    # Look for option in JSON file;
    script=$(jq --argjson pos "$OPTION" '.[] | select(.file_menu_position == $pos)' "$DES_SUBMENU_JSON")
  fi

  # Return to main menu option check:
  if [ "$OPTION" == "$BACK_TO_MAIN_MENU_UP" ] || [ "$OPTION" == "$BACK_TO_MAIN_MENU_DOWN" ]; then
    unset DES_SUBMENU_ACTIVE
    return 0
  fi

  # Return 1 if no match found:
  [ -z "$script" ] && return 1

  local script_name
  script_name=$(jq -r '.file_name' <<< "$script")

  local script_path="$DES_PACKAGES_SCRIPTS_PATH/$script_name"

  # Execute do_work function from the script:
  bash "$script_path" do_work

  return 0
}
