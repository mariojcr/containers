#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mario Campos <https://github.com/mariojcr>
# SPDX-License-Identifier: Apache-2.0
#
# A Steam dedicated server in a container: DepotDownloader installs or updates
# the app, then the binary runs, native or under Proton when it is a .exe.
#
# APP_ID and EXE_PATH are the minimum. Every variable is documented in the
# image's README; only what the name does not say is commented here.
set -uo pipefail

# --- input -----------------------------------------------------------------
GAME_DIR="${GAME_DIR:-/game}"
WORK_DIR="${WORK_DIR:-${GAME_DIR}}"
APP_ID="${APP_ID:-}"
EXE_PATH="${EXE_PATH:-}"
SERVER_ARGS="${SERVER_ARGS:-}"

APP_OS="${APP_OS:-}"
APP_ARCH="${APP_ARCH:-64}"
DEPOT_ID="${DEPOT_ID:-}"
MANIFEST_ID="${MANIFEST_ID:-}"
APP_BRANCH="${APP_BRANCH:-}"
BRANCH_PASSWORD="${BRANCH_PASSWORD:-}"
STEAM_USERNAME="${STEAM_USERNAME:-}"
STEAM_PASSWORD="${STEAM_PASSWORD:-}"
MAX_DOWNLOADS="${MAX_DOWNLOADS:-8}"
VALIDATE="${VALIDATE:-false}"
SKIP_UPDATE="${SKIP_UPDATE:-false}"
UPDATE_REQUIRED="${UPDATE_REQUIRED:-false}"

USE_PROTON="${USE_PROTON:-auto}"
PROTON_DIR="${PROTON_DIR:-/opt/proton}"
XVFB_NEEDED="${XVFB_NEEDED:-false}"
PRE_START_CMD="${PRE_START_CMD:-}"

READ_LOGS_FILE="${READ_LOGS_FILE:-}"
LOG_WAIT_SECONDS="${LOG_WAIT_SECONDS:-600}"
# kept for compatibility: it used to be required, and says whether to follow
# the game's log file
BACKGROUND_PROCESS="${BACKGROUND_PROCESS:-true}"
STOP_SIGNAL="${STOP_SIGNAL:-TERM}"
STOP_GRACE_SECONDS="${STOP_GRACE_SECONDS:-80}"

DEPOTDOWNLOADER="/opt/depotdownloader/DepotDownloader"

die() { echo "$*" >&2; exit 1; }

[ -n "${EXE_PATH}" ] || die "EXE_PATH is not set (the server binary). Exiting."
[ -n "${APP_ID}" ] || [ "${SKIP_UPDATE}" = "true" ] \
  || die "APP_ID is not set (or set SKIP_UPDATE=true to run what is already installed). Exiting."
[ -z "${MANIFEST_ID}" ] || [ -n "${DEPOT_ID}" ] \
  || die "MANIFEST_ID needs DEPOT_ID (a manifest belongs to one depot). Exiting."
[ -z "${STEAM_PASSWORD}" ] || [ -n "${STEAM_USERNAME}" ] \
  || die "STEAM_PASSWORD needs STEAM_USERNAME. Exiting."

# A .exe runs under Proton, anything else runs native. USE_PROTON forces it
# either way, for the servers whose binary is named like neither.
case "${USE_PROTON}" in
  auto) case "${EXE_PATH,,}" in *.exe) USE_PROTON=true ;; *) USE_PROTON=false ;; esac ;;
  true|false) ;;
  *) die "USE_PROTON must be auto, true or false. Exiting." ;;
esac
# which depot to pull: the Windows one under Proton, the native one otherwise
[ -n "${APP_OS}" ] || { [ "${USE_PROTON}" = "true" ] && APP_OS=windows || APP_OS=linux; }

if [ "${USE_PROTON}" = "true" ]; then
  PROTON="${PROTON_DIR}/proton"
  [ -x "${PROTON}" ] || die "No Proton at ${PROTON}. Exiting."
  export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-/opt/steam}"
  # The Wine prefix lives in the volume: building it on every start costs time
  # and throws away whatever the game wrote to its registry. To start over,
  # delete the directory.
  export STEAM_COMPAT_DATA_PATH="${STEAM_COMPAT_DATA_PATH:-${GAME_DIR}/.compatdata/${APP_ID:-app}}"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}"
fi

# --- install or update -----------------------------------------------------
# DepotDownloader keeps its state (the installed manifest) in
# <GAME_DIR>/.DepotDownloader, so it survives the container, and it only
# deletes files that were in the previous manifest and are gone from the new
# one — saves, logs and configuration are never in a manifest.
update_app() {
  local args=(-app "${APP_ID}" -os "${APP_OS}" -osarch "${APP_ARCH}"
              -dir "${GAME_DIR}" -max-downloads "${MAX_DOWNLOADS}")
  [ -n "${DEPOT_ID}" ] && args+=(-depot "${DEPOT_ID}")
  [ -n "${MANIFEST_ID}" ] && args+=(-manifest "${MANIFEST_ID}")
  [ -n "${APP_BRANCH}" ] && args+=(-branch "${APP_BRANCH}")
  [ -n "${BRANCH_PASSWORD}" ] && args+=(-branchpassword "${BRANCH_PASSWORD}")
  [ -n "${STEAM_USERNAME}" ] && args+=(-username "${STEAM_USERNAME}")
  { [ "${1:-}" = "validate" ] || [ "${VALIDATE}" = "true" ]; } && args+=(-validate)
  if [ -n "${STEAM_PASSWORD}" ]; then
    # over stdin, so it stays out of the process command line
    printf '%s\n' "${STEAM_PASSWORD}" | "${DEPOTDOWNLOADER}" "${args[@]}"
  else
    "${DEPOTDOWNLOADER}" "${args[@]}"
  fi
}

if [ "${SKIP_UPDATE}" = "true" ]; then
  echo "SKIP_UPDATE=true: leaving Steam alone, running what is in ${GAME_DIR}"
elif ! update_app; then
  # The retry validates: it compares the disk against the manifest chunk by
  # chunk and redoes only what does not match, which also repairs a half-done
  # install.
  echo "Update of app ${APP_ID} failed; retrying with validation..."
  if ! update_app validate; then
    # Steam being down should not keep the server from starting: with the game
    # installed it runs the build on disk. UPDATE_REQUIRED=true forbids that.
    if [ "${UPDATE_REQUIRED}" = "true" ] || [ ! -f "${EXE_PATH}" ]; then
      die "Update of app ${APP_ID} failed and there is no usable install. Exiting."
    fi
    echo "WARNING: update of app ${APP_ID} failed; starting the installed build as-is."
  fi
fi

if [ -n "${PRE_START_CMD}" ]; then
  echo "Pre-start: ${PRE_START_CMD}"
  bash -c "${PRE_START_CMD}" || die "Pre-start command failed. Exiting."
fi

# --- start -----------------------------------------------------------------
cd "${WORK_DIR}" || die "No ${WORK_DIR}. Exiting."

run_server() {
  local cmd=()
  # without a DISPLAY, Wine hangs in some games before it loads the exe
  [ "${XVFB_NEEDED}" = "true" ] && cmd+=(xvfb-run --auto-servernum)
  [ "${USE_PROTON}" = "true" ] && cmd+=("${PROTON}" run)
  cmd+=("${EXE_PATH}")
  # the server's arguments: the container's own, verbatim (those keep quotes
  # and spaces), or else SERVER_ARGS split on whitespace
  if [ "$#" -gt 0 ]; then
    cmd+=("$@")
  elif [ -n "${SERVER_ARGS}" ]; then
    local extra=()
    read -ra extra <<< "${SERVER_ARGS}"
    cmd+=("${extra[@]}")
  fi
  echo "Starting: ${cmd[*]}"
  "${cmd[@]}" &
  SERVER_PID=$!
}

# On stop the orchestrator sends SIGTERM to pid 1 (this script): it is passed
# on to the server, which gets time to save and exit before anyone kills it
# (Nomad's kill_timeout must be longer than STOP_GRACE_SECONDS).
shutdown() {
  echo "Stopping game server (pid ${SERVER_PID})..."
  pkill "-${STOP_SIGNAL}" -P "${SERVER_PID}" 2>/dev/null
  kill "-${STOP_SIGNAL}" "${SERVER_PID}" 2>/dev/null
  for _ in $(seq 1 "${STOP_GRACE_SECONDS}"); do
    kill -0 "${SERVER_PID}" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "${SERVER_PID}" 2>/dev/null; then
    echo "Server still running after ${STOP_GRACE_SECONDS}s; killing it..."
    if [ "${USE_PROTON}" = "true" ]; then
      "${PROTON_DIR}/files/bin/wineserver" -k 2>/dev/null
    fi
    pkill -KILL -P "${SERVER_PID}" 2>/dev/null
    kill -KILL "${SERVER_PID}" 2>/dev/null
  fi
  [ -n "${TAIL_PID:-}" ] && kill "${TAIL_PID}" 2>/dev/null
  exit 0
}
trap shutdown TERM INT

run_server "$@"

# Many servers write their log to a file instead of stdout: follow it so it
# shows up in the container's logs. On a brand new server the file is not
# there yet.
if [ "${BACKGROUND_PROCESS}" = "true" ] && [ -n "${READ_LOGS_FILE}" ]; then
  for _ in $(seq 1 "${LOG_WAIT_SECONDS}"); do
    [ -f "${READ_LOGS_FILE}" ] && break
    kill -0 "${SERVER_PID}" 2>/dev/null || { echo "Server exited before writing ${READ_LOGS_FILE}"; wait "${SERVER_PID}"; exit $?; }
    sleep 1
  done
  if [ -f "${READ_LOGS_FILE}" ]; then
    tail -n +1 -F "${READ_LOGS_FILE}" &
    TAIL_PID=$!
  else
    echo "No log file after ${LOG_WAIT_SECONDS}s; running without log output"
  fi
fi

# If the server dies the task ends (and the orchestrator restarts it); the
# trap keeps serving SIGTERM in the meantime
wait "${SERVER_PID}"
RC=$?
[ -n "${TAIL_PID:-}" ] && kill "${TAIL_PID}" 2>/dev/null
echo "Game server exited with code ${RC}"
exit "${RC}"
