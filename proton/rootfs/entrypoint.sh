#!/bin/bash

# check environment variables
if [ -z "${APP_ID}" ]; then
  echo "APP_ID environment variable is not set. Exiting."
  exit 1
fi

if [ -z "${EXE_PATH}" ]; then
  echo "EXE_PATH environment variable is not set. Exiting."
  exit 1
fi

if [ -z "${BACKGROUND_PROCESS}" ]; then
  echo "BACKGROUND_PROCESS environment variable is not set. Exiting."
  exit 1
fi

export STEAM_COMPAT_CLIENT_INSTALL_PATH="/steamcmd"
export STEAM_COMPAT_DATA_PATH="/steamcmd/steamapps/compatdata/${APP_ID}"
mkdir -p "${STEAM_COMPAT_DATA_PATH}"

rm -f /game/steamapps/appmanifest_"${APP_ID}".acf

# +app_license_request forces SteamCMD to refresh the app license/configuration
# before the update. This avoids the recurring "ERROR! Failed to install app
# 'XXX' (Missing configuration)" failure observed with several anonymous-eligible
# dedicated server apps (e.g. Conan Exiles - 443030) whose package metadata is
# not picked up correctly by a fresh SteamCMD client.
/steamcmd/steamcmd.sh \
  +@sSteamCmdForcePlatformType windows \
  +force_install_dir /game \
  +login anonymous \
  +app_license_request "${APP_ID}" \
  +app_update "${APP_ID}" validate \
  +quit

if [ "${BACKGROUND_PROCESS}" = "true" ]; then
  /steamcmd/compatibilitytools.d/GE-Proton"${PROTON_VERSION}"/proton run "${EXE_PATH}" &
  if [ -n "${READ_LOGS_FILE}" ] && [ -f "${READ_LOGS_FILE}" ]; then
    exec tail -f "${READ_LOGS_FILE}"
  else
    tail -f /dev/null
  fi
else
  /steamcmd/compatibilitytools.d/GE-Proton"${PROTON_VERSION}"/proton run "${EXE_PATH}"
fi
