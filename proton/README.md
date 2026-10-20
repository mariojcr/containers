# proton

Un servidor dedicado de Steam dentro de un contenedor: la imagen instala o
actualiza la app con [DepotDownloader](https://github.com/SteamRE/DepotDownloader)
y arranca el binario, nativo o de Windows bajo
[GE-Proton](https://github.com/GloriousEggroll/proton-ge-custom).

`ghcr.io/mariojcr/proton:<versión de GE-Proton>` (p. ej. `11-7`), y
`…:<versión>-<sha>` para fijar una build concreta.

## Lo mínimo

```hcl
env {
  APP_ID   = "2278520"                      # Enshrouded Dedicated Server
  EXE_PATH = "/game/enshrouded_server.exe"  # .exe → se ejecuta bajo Proton
}
```

El juego vive en `/game`, que debe ser un volumen: ahí van la instalación, las
partidas y el estado de DepotDownloader (`.DepotDownloader/`, el manifest
instalado, lo que permite actualizar por diferencias).

## Variables

### Qué instalar

| Variable | Por defecto | Para qué |
|---|---|---|
| `APP_ID` | — | La app de Steam. Obligatoria salvo con `SKIP_UPDATE=true` |
| `GAME_DIR` | `/game` | Dónde se instala |
| `APP_OS` | `windows` con Proton, `linux` sin él | Qué depot bajar |
| `APP_ARCH` | `64` | 32 o 64 bits |
| `DEPOT_ID` | — | Un solo depot en vez de todos los de la app |
| `MANIFEST_ID` | — | Clava una build exacta (necesita `DEPOT_ID`) |
| `APP_BRANCH` | `public` | Una rama (beta, experimental…) |
| `BRANCH_PASSWORD` | — | Si la rama la pide |
| `STEAM_USERNAME` | — | Para apps que no se bajan en anónimo |
| `STEAM_PASSWORD` | — | Se pasa por stdin, no por la línea de comandos |
| `VALIDATE` | `false` | Validar siempre contra el manifest (lento) |
| `MAX_DOWNLOADS` | `8` | Descargas en paralelo |
| `SKIP_UPDATE` | `false` | No tocar Steam: arranca lo que haya en el volumen |
| `UPDATE_REQUIRED` | `false` | Abortar si el update falla, en vez de arrancar con lo instalado |

### Cómo arrancarlo

| Variable | Por defecto | Para qué |
|---|---|---|
| `EXE_PATH` | — | El binario del servidor. Obligatoria |
| `SERVER_ARGS` | — | Argumentos, partidos por espacios. Si necesitas comillas, pásalos como `args` de la tarea: se usan tal cual |
| `USE_PROTON` | `auto` | `auto` mira si acaba en `.exe`; `true`/`false` lo fuerzan |
| `WORK_DIR` | `GAME_DIR` | Directorio de trabajo del servidor |
| `XVFB_NEEDED` | `false` | Algunos juegos de Windows se cuelgan sin `DISPLAY` |
| `PRE_START_CMD` | — | Un comando antes de arrancar (si falla, no arranca) |
| `STEAM_COMPAT_DATA_PATH` | `GAME_DIR/.compatdata/APP_ID` | El prefijo de Wine. Vive en el volumen: para empezar de cero, se borra |

### Logs y parada

| Variable | Por defecto | Para qué |
|---|---|---|
| `READ_LOGS_FILE` | — | Si el juego escribe su log a fichero, se sigue y sale por stdout |
| `LOG_WAIT_SECONDS` | `600` | Cuánto esperar a que aparezca ese fichero la primera vez |
| `BACKGROUND_PROCESS` | `true` | A `false` no sigue el log |
| `STOP_SIGNAL` | `TERM` | La señal que espera el juego para guardar y salir |
| `STOP_GRACE_SECONDS` | `80` | Cuánto se le da antes de matarlo. El `kill_timeout` de Nomad debe ser mayor |

## Ejemplos

Windows bajo Proton, con log a fichero (Enshrouded):

```hcl
env {
  APP_ID         = "2278520"
  EXE_PATH       = "/game/enshrouded_server.exe"
  READ_LOGS_FILE = "/game/logs/enshrouded_server.log"
  XVFB_NEEDED    = "true"
}
```

Nativo de Linux con argumentos (Valheim):

```hcl
env {
  APP_ID      = "896660"
  EXE_PATH    = "/game/valheim_server.x86_64"
  SERVER_ARGS = "-nographics -batchmode -name MiServer -port 2456 -world Dedicated"
}
```

Build clavada, para que un reinicio no se traiga un parche sin avisar:

```hcl
env {
  APP_ID      = "2278520"
  DEPOT_ID    = "2278521"
  MANIFEST_ID = "6823302667609042502"
  EXE_PATH    = "/game/enshrouded_server.exe"
}
```

## Detalles que importan

- **Las partidas no se tocan.** DepotDownloader solo borra ficheros que
  estaban en el manifest anterior y ya no están en el nuevo; `savegame/`,
  `logs/` y la configuración nunca han estado en un manifest.
- **Un Steam caído no deja el servidor abajo.** Si el update falla dos veces
  (la segunda validando) y el juego ya está instalado, arranca con lo que hay
  y lo avisa en el log. `UPDATE_REQUIRED=true` recupera el comportamiento de
  abortar.
- **Migrar desde una instalación hecha con steamcmd** no re-descarga nada: la
  primera pasada valida el disco contra el manifest chunk a chunk (7,6 GB en
  21 s en un VPS de OVH) y baja solo lo que falte.
- `steamclient.so` sale de la redistribuible oficial (app 1007), no de
  steamcmd, en las rutas de siempre (`~/.steam/sdk32`, `~/.steam/sdk64`).
