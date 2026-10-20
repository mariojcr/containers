#!/bin/bash
# Un servidor dedicado de Steam dentro de un contenedor: instala o actualiza la
# app con DepotDownloader y arranca el binario, nativo o de Windows bajo Proton.
#
# Lo mínimo es APP_ID y EXE_PATH. Todas las variables están en el README de la
# imagen; aquí solo se comenta lo que no se ve en el nombre.
set -uo pipefail

# --- entrada ---------------------------------------------------------------
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
XVFB_NEEDED="${XVFB_NEEDED:-false}"
PRE_START_CMD="${PRE_START_CMD:-}"

READ_LOGS_FILE="${READ_LOGS_FILE:-}"
LOG_WAIT_SECONDS="${LOG_WAIT_SECONDS:-600}"
# compatibilidad: antes era obligatoria y decía si seguir el log del juego
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

# Un .exe se ejecuta bajo Proton; cualquier otra cosa, nativa. USE_PROTON lo
# fuerza en los dos sentidos (hay servidores nativos con nombres raros).
case "${USE_PROTON}" in
  auto) case "${EXE_PATH,,}" in *.exe) USE_PROTON=true ;; *) USE_PROTON=false ;; esac ;;
  true|false) ;;
  *) die "USE_PROTON must be auto, true or false. Exiting." ;;
esac
# El depot que toca: el de Windows si corre bajo Proton, el nativo si no
[ -n "${APP_OS}" ] || { [ "${USE_PROTON}" = "true" ] && APP_OS=windows || APP_OS=linux; }

if [ "${USE_PROTON}" = "true" ]; then
  [ -n "${PROTON_VERSION:-}" ] || die "PROTON_VERSION is not set in the image. Exiting."
  PROTON="/steamcmd/compatibilitytools.d/GE-Proton${PROTON_VERSION}/proton"
  [ -x "${PROTON}" ] || die "No Proton at ${PROTON}. Exiting."
  export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-/steamcmd}"
  # El prefijo vive en el volumen: crearlo en cada arranque cuesta tiempo y
  # pierde lo que el juego escriba en su registro. Para empezar de cero, se
  # borra el directorio.
  export STEAM_COMPAT_DATA_PATH="${STEAM_COMPAT_DATA_PATH:-${GAME_DIR}/.compatdata/${APP_ID:-app}}"
  mkdir -p "${STEAM_COMPAT_DATA_PATH}"
fi

# --- instalar o actualizar -------------------------------------------------
# DepotDownloader (SteamRE) en lugar de steamcmd: código de salida de verdad,
# estado propio en <GAME_DIR>/.DepotDownloader y los depots por WebSocket (443).
# Solo borra ficheros que estaban en el manifest anterior y ya no están en el
# nuevo, así que las partidas, los logs y la configuración no se tocan nunca.
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
    # por stdin: así no queda en la línea de comandos del proceso
    printf '%s\n' "${STEAM_PASSWORD}" | "${DEPOTDOWNLOADER}" "${args[@]}"
  else
    "${DEPOTDOWNLOADER}" "${args[@]}"
  fi
}

if [ "${SKIP_UPDATE}" = "true" ]; then
  echo "SKIP_UPDATE=true: Steam untouched, running what is in ${GAME_DIR}"
elif ! update_app; then
  # El segundo intento valida: compara el disco contra el manifest chunk a
  # chunk y rehace solo lo que no cuadre (sirve para una instalación a medias).
  echo "Update of app ${APP_ID} failed; retrying with validation..."
  if ! update_app validate; then
    # Un Steam caído no debería dejar el servidor sin arrancar: si el juego ya
    # está instalado se sigue con lo que hay. UPDATE_REQUIRED=true lo impide.
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

# --- arrancar --------------------------------------------------------------
cd "${WORK_DIR}" || die "No ${WORK_DIR}. Exiting."

run_server() {
  local cmd=()
  # Sin DISPLAY, Wine se queda colgado en algunos juegos antes de cargar el exe
  [ "${XVFB_NEEDED}" = "true" ] && cmd+=(xvfb-run --auto-servernum)
  [ "${USE_PROTON}" = "true" ] && cmd+=("${PROTON}" run)
  cmd+=("${EXE_PATH}")
  # Los argumentos del servidor: los del propio contenedor tal cual (los que
  # respetan comillas y espacios) o, si no hay, SERVER_ARGS partido por espacios
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

# Al parar la tarea, el orquestador manda SIGTERM al proceso 1 (este script):
# se reenvía al servidor y se le da tiempo a guardar y salir antes de que lo
# maten a él (el kill_timeout de Nomad debe ser mayor que STOP_GRACE_SECONDS).
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
      "${PROTON%/proton}/files/bin/wineserver" -k 2>/dev/null
    fi
    pkill -KILL -P "${SERVER_PID}" 2>/dev/null
    kill -KILL "${SERVER_PID}" 2>/dev/null
  fi
  [ -n "${TAIL_PID:-}" ] && kill "${TAIL_PID}" 2>/dev/null
  exit 0
}
trap shutdown TERM INT

run_server "$@"

# Muchos servidores escriben su log en un fichero en vez de a stdout: se sigue
# para que salga por los logs del contenedor. En uno recién creado el fichero
# aún no existe.
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

# Si el servidor muere, la tarea termina (y el orquestador la reinicia); el
# trap sigue atendiendo SIGTERM mientras tanto
wait "${SERVER_PID}"
RC=$?
[ -n "${TAIL_PID:-}" ] && kill "${TAIL_PID}" 2>/dev/null
echo "Game server exited with code ${RC}"
exit "${RC}"
