#!/bin/bash
#portappm
APPS_DIRECTORY=""
COMMAND=""
APP_NAME=""

# Get cli flags
while getopts "c:a:d:" o; do
  case "${o}" in
    a)
      APP_NAME="${OPTARG}"
      ;;
    c)
      COMMAND="${OPTARG}"
      ;;
    d)
      APPS_DIRECTORY="${OPTARG}"
      ;;
    *)
      echo "Fatal Error! Invalid flag '${o}' found!"
      exit 1
  esac
done

# Parse main directory with applications
if [[ -z $APPS_DIRECTORY ]]; then APPS_DIRECTORY="$HOME/Apps"; fi
if [[ ${APPS_DIRECTORY:0-1} == "/" ]]; then APPS_DIRECTORY="${APPS_DIRECTORY%?}"; fi
if [[ ! -d $APPS_DIRECTORY ]]; then
  echo "'$APPS_DIRECTORY' doesn't exist!"
  exit 1
fi

# Returns with fail(1) if any of the required files are missing, otherwise returns with success(0)
check_valid_app () {
  CHECK_APP_NAME=$1
  CHECK_APP_DIR="$APPS_DIRECTORY/$APP_NAME"
  if [[ ! -f "$CHECK_APP_DIR/app.conf" ]]; then
    echo "$CHECK_APP_NAME | app.conf not found!"
    return 1
  fi;
  if [[ ! -f "$CHECK_APP_DIR/app-update.sh" ]]; then
    echo "$CHECK_APP_NAME | app-update.sh not found!"
    return 1
  fi;
  if [[ ! -f "$CHECK_APP_DIR/run.sh" ]]; then
    echo "$CHECK_APP_NAME | run.sh not found!"
    return 1
  fi;
  return 0
}

# Reads the config file of the app and saves the configuration into variables accessible by the caller
read_app_config () {
  CONFIG_APP_NAME=$1
  CONFIG_FILE="$APPS_DIRECTORY/$CONFIG_APP_NAME/app.conf"
  SECTION="None"
  while IFS= read -r LINE
  do
    # Check current config section
    if [[ $LINE =~ ^\ *\[.*\]\ *$ ]]; then #Regex that checks for characters between [] and allows spaces around
        SECTION=$(echo "$LINE" | awk -F'[][]' '{print $2}')
        continue
    fi
    # Read Key-Value pairs
    if [[ $LINE =~ ^\ *\#.*$ ]]; then continue; fi
    KEY=$(echo "$LINE" | awk -F' *=' '{print $1}' | sed 's/^[[:space:]]*//')
    VALUE=$(
      echo "$LINE" | awk -F: '{ n=index($0,"=");print substr($0,n+1)}' | # Splits by the 1st "=" and returns the 2nd half
      sed 's/[[:space:]]*$//' | sed 's/^[[:space:]]*//' # Removes trailing spaces
    )
    
    # Save values in config into variables
    if [[ $SECTION == "General" ]]; then
      if [[ $KEY == "Exec" ]];then EXECUTABLE_PATH=$VALUE;fi
      if [[ $KEY == "Type" ]];then EXECUTABLE_TYPE=$VALUE;fi
      if [[ $KEY == "ExtractFolder" ]];then EXTRACT_FOLDER=$VALUE;fi
      if [[ $KEY == "ArchiveStrip" ]];then ARCHIVE_STRIP=$VALUE;fi
      if [[ $KEY == "RemoveBeforeUpdate" ]];then RM_BEFORE_UPDATE=$VALUE;fi
    elif [[ $SECTION == "Desktop" ]]; then
      if [[ $KEY == "Name" ]];then DESKTOP_NAME=$VALUE;fi
      if [[ $KEY == "Icon" ]];then DESKTOP_ICON=$VALUE;fi
      if [[ $KEY == "GenericName" ]];then DESKTOP_GENERIC_NAME=$VALUE;fi
      if [[ $KEY == "Terminal" ]];then DESKTOP_TERMINAL=$VALUE;fi
      if [[ $KEY == "NoDisplay" ]];then DESKTOP_NO_DISPLAY=$VALUE;fi
      if [[ $KEY == "Arguments" ]];then EXECUTABLE_ARGS=$VALUE;fi
      if [[ $KEY == "EnvVariables" ]];then EXECUTABLE_ENV=$VALUE;fi
      if [[ $KEY == "PreLaunch" ]];then EXECUTABLE_PRE_LAUNCH=$VALUE;fi
    fi
  done < "$CONFIG_FILE"
}

# Checks for available updates and updates the app if possible
update_app () {
  APP_NAME=$1
  APP_DIR="$APPS_DIRECTORY/$APP_NAME"
  VERSION_FILE="$APP_DIR/.version"
  INSTALLED_VERSION=$(awk 'NR==1{ print; exit }' "$VERSION_FILE")
  #RM_BEFORE_UPDATE=false
  ARCHIVE_STRIP=0
  UPDATE_SCRIPT="$APP_DIR/app-update.sh"
  # Get variables from a config file
  read_app_config "$APP_NAME"
  if [[ -z $EXECUTABLE_PATH ]]; then
    echo "$APP_NAME | Configuration failure! 'General.Exec' is not set! Make sure to set it to a valid file name!"
    return 1
  fi
  # Check if newer version is available
  LATEST_VERSION="$("$UPDATE_SCRIPT" -v)"
  if [[ -z $LATEST_VERSION ]]; then # Handle empty error
    echo "$APP_NAME | Failed to get the latest version of the app!"
    return 1
  fi
  if [[ $LATEST_VERSION =~ ^Fatal\ Error\!.*$ ]]; then # Handle errors
    echo "$APP_NAME | $LATEST_VERSION"
    return 1
  fi
  if [[ "$INSTALLED_VERSION" == "$LATEST_VERSION" ]]; then
    echo "$APP_NAME | Up To Date! Version: $LATEST_VERSION"
    return 0
  fi
  # Continue if an update is available
  echo "$APP_NAME | New version found! $LATEST_VERSION (Installed version: $INSTALLED_VERSION)"
  DOWNLOAD_URL="$("$UPDATE_SCRIPT" -u)"
  if [[ -z $DOWNLOAD_URL ]]; then # Handle empty error
    echo "$APP_NAME | Failed to get the download URL for the app!"
    return 1
  fi
  if [[ $DOWNLOAD_URL =~ ^Fatal\ Error\!.*$ ]]; then # Handle errors
    echo "$APP_NAME | $DOWNLOAD_URL"
    return 1
  fi

  # Download the update
  echo "$APP_NAME | Downloading new version from '$DOWNLOAD_URL'."
  TEMP_FILE="$APP_DIR/temp-download-file"
  BIN_PATH="$APP_DIR/$EXECUTABLE_PATH"
  wget --content-disposition -q --show-progress "$DOWNLOAD_URL" -O "$TEMP_FILE"

  # Extract the downloaded file
  if [[ "$EXECUTABLE_TYPE" == "SingleBin" ]]; then
    echo "$APP_NAME | Saving the updated binary to '$BIN_PATH'."
    mv -f "$TEMP_FILE" "$BIN_PATH"
  elif [[ "$EXECUTABLE_TYPE" == "BinArchive" ]]; then
    EXTRACT_PATH="$APP_DIR"
    if [[ -n $EXTRACT_FOLDER ]]; then EXTRACT_PATH="$APP_DIR/$EXTRACT_FOLDER"; fi
    if [[ ! -d $EXTRACT_PATH ]]; then mkdir -p "$EXTRACT_PATH"; fi
    echo "$APP_NAME | Extracting the updated archive to '$EXTRACT_PATH'."
    tar -xf "$TEMP_FILE" -C "$EXTRACT_PATH" --strip "$ARCHIVE_STRIP" --overwrite
    rm -f "$TEMP_FILE"
  else
    echo "$APP_NAME | Configuration failure! 'General.Type' is set to an unrecognised value - '$EXECUTABLE_TYPE' Allowed values: 'SingleBin','BinArchive'"
    rm -f "$TEMP_FILE"
    return 1
  fi

  # Finishing up
  echo "$APP_NAME | Setting executable permissions for the binary and saving the installed version."
  chmod +x "$BIN_PATH"
  echo "$LATEST_VERSION" > "$VERSION_FILE"
  echo "$APP_NAME | Done updating!"
}

get_app_executable () {
  ENV_STRING=""
  read_app_config "$APP_NAME" 1>&2> /dev/null
  if [[ -n $EXECUTABLE_ENV ]]; then
    ENV_STRING="env $EXECUTABLE_ENV"
  fi
  EXEC_PATH="$APPS_DIRECTORY/$APP_NAME/$EXECUTABLE_PATH"
  echo "$ENV_STRING $EXECUTABLE_PRE_LAUNCH '$EXEC_PATH' $EXECUTABLE_ARGS"
}

# Verifies basic properties of the required files to check if they are valid and corrects them if they aren't
verify_app () {
  return
}

# Forces reinstallation of the app
reinstall_app () {
  return
}

# Will be used for downloading and extracting the file instead of having the logic in the `update_app` function
install_app() {
  return
}

run_app () {
  APP_NAME=$1
  APP_EXEC=$(get_app_executable "$APP_NAME")
  echo "Running:"
  echo "$APP_EXEC"
  eval "$APP_EXEC"
}

update_all_apps () {
  for APP_PATH in "$APPS_DIRECTORY"/*/; do
    if [ ! -d "$APP_PATH" ]; then continue; fi # Skip files
    APP_NAME="$(basename "$APP_PATH")"
    if check_valid_app "$APP_NAME"; then
        update_app "$APP_NAME"
    else
      for SUB_APP_PATH in "$APP_PATH"/*/; do
        if [ ! -d "$SUB_APP_PATH" ]; then continue; fi # Skip files
        SUB_APP_NAME="$APP_NAME/$(basename "$SUB_APP_PATH")"
        if check_valid_app "$SUB_APP_NAME"; then
          update_app "$SUB_APP_NAME"
        fi
      done
      continue
    fi
  done
}

create_app_shortcut() {
  APP_NAME=$1
  DESKTOP_FILE_DIR="/home/pavel/.local/share/applications/Portable"
  APP_DESKTOP_FILE="$DESKTOP_FILE_DIR/$APP_NAME.desktop"
  if [[ -f "$APP_DESKTOP_FILE" ]]; then
    echo "Desktop file '$APP_DESKTOP_FILE' already exists."
    return 0
  fi
  # Get desktop entries
  DESKTOP_EXEC=$(get_app_executable "$APP_NAME")
  read_app_config "$APP_NAME"

  echo "Creating desktop file '$APP_DESKTOP_FILE'."
  echo "[Desktop Entry]" > "$APP_DESKTOP_FILE"
  {
    echo "Exec=$DESKTOP_EXEC";
    echo "Path=$APPS_DIRECTORY/$APP_NAME/";
    echo "Type=Application";
    echo "Name=$DESKTOP_NAME";
    echo "Icon=$DESKTOP_ICON";
    echo "GenericName=$DESKTOP_GENERIC_NAME";
    echo "Comment=$DESKTOP_COMMENT";
    echo "MimeType=$DESKTOP_MIME_TYPE";
    echo "Categories=$DESKTOP_CATEGORIES";
    echo "Keywords=$DESKTOP_KEYWORDS";
    echo "Terminal=$DESKTOP_TERMINAL";
    echo "NoDisplay=$DESKTOP_NO_DISPLAY";
  } >> "$APP_DESKTOP_FILE"
}

create_all_app_shortcuts () {
  return
}

add_app () {
  NEW_APP_NAME=$1
  NEW_APP_DIR="$APPS_DIRECTORY/$NEW_APP_NAME"
  NEW_APP_BASENAME="$(basename "$NEW_APP_DIR")"
  mkdir -p "$NEW_APP_DIR"
  touch "$NEW_APP_DIR/run.sh"
  chmod +x "$NEW_APP_DIR/run.sh"
  touch "$NEW_APP_DIR/app-update.sh"
  chmod +x "$NEW_APP_DIR/app-update.sh"
  return
}

if [[ $COMMAND = "run" ]]; then
  run_app "$APP_NAME"
elif [[ "$COMMAND" = "update" ]]; then
  if [[ -z $APP_NAME ]]; then
    update_all_apps
  else
    update_app "$APP_NAME"
  fi
elif [[ "$COMMAND" = "add" ]]; then
  exit
elif [[ "$COMMAND" = "shortcut" ]]; then
  if [[ -z $APP_NAME ]]; then
    create_all_app_shortcuts
  else
    create_app_shortcut "$APP_NAME"
  fi
fi
