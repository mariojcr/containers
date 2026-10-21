<!--
SPDX-FileCopyrightText: 2026 Mario Campos <https://github.com/mariojcr>
SPDX-License-Identifier: Apache-2.0
-->

# proton

A Steam dedicated server in a container. The image installs or updates the app
with [DepotDownloader](https://github.com/SteamRE/DepotDownloader) and starts
the server binary, native or — when it is an `.exe` — under
[GE-Proton](https://github.com/GloriousEggroll/proton-ge-custom).

`ghcr.io/mariojcr/proton:<GE-Proton version>` (for example `11-11`), plus
`…:<version>-<short sha>` to pin an exact build.

## The minimum

```hcl
env {
  APP_ID   = "2278520"                      # Enshrouded Dedicated Server
  EXE_PATH = "/game/enshrouded_server.exe"  # an .exe runs under Proton
}
```

The game lives in `/game`, which must be a volume: the install, the saves and
DepotDownloader's state (`.DepotDownloader/`, the installed manifest, which is
what makes the next update a delta) all go there.

## Variables

### What to install

| Variable | Default | What for |
|---|---|---|
| `APP_ID` | — | The Steam app. Required unless `SKIP_UPDATE=true` |
| `GAME_DIR` | `/game` | Where it is installed |
| `APP_OS` | `windows` under Proton, `linux` otherwise | Which depot to pull |
| `APP_ARCH` | `64` | 32- or 64-bit |
| `DEPOT_ID` | — | One depot instead of every depot of the app |
| `MANIFEST_ID` | — | Pin an exact build (needs `DEPOT_ID`) |
| `APP_BRANCH` | `public` | A branch (beta, experimental…) |
| `BRANCH_PASSWORD` | — | If the branch asks for one |
| `STEAM_USERNAME` | — | For apps that anonymous cannot download |
| `STEAM_PASSWORD` | — | Passed over stdin, not on the command line |
| `VALIDATE` | `false` | Always validate against the manifest (slow) |
| `MAX_DOWNLOADS` | `8` | Parallel chunk downloads |
| `SKIP_UPDATE` | `false` | Leave Steam alone and run what is in the volume |
| `UPDATE_REQUIRED` | `false` | Abort when the update fails instead of starting the installed build |

### How to start it

| Variable | Default | What for |
|---|---|---|
| `EXE_PATH` | — | The server binary. Required |
| `SERVER_ARGS` | — | Arguments, split on whitespace. If you need quoting, pass them as the task's `args` instead: those are used verbatim |
| `USE_PROTON` | `auto` | `auto` goes by the `.exe` suffix; `true`/`false` force it |
| `WORK_DIR` | `GAME_DIR` | The server's working directory |
| `XVFB_NEEDED` | `false` | Some Windows games hang without a `DISPLAY` |
| `PRE_START_CMD` | — | A command to run first; if it fails, the server does not start |
| `PROTON_DIR` | `/opt/proton` | Where GE-Proton is |
| `STEAM_COMPAT_DATA_PATH` | `GAME_DIR/.compatdata/APP_ID` | The Wine prefix. It lives in the volume; delete the directory to start over |

### Logs and shutdown

| Variable | Default | What for |
|---|---|---|
| `READ_LOGS_FILE` | — | If the game writes its log to a file, follow it onto stdout |
| `LOG_WAIT_SECONDS` | `600` | How long to wait for that file to appear the first time |
| `BACKGROUND_PROCESS` | `true` | `false` does not follow the log |
| `STOP_SIGNAL` | `TERM` | The signal the game expects in order to save and exit |
| `STOP_GRACE_SECONDS` | `80` | How long it gets before being killed. Nomad's `kill_timeout` must be longer |

## Examples

Windows under Proton, logging to a file (Enshrouded):

```hcl
env {
  APP_ID         = "2278520"
  EXE_PATH       = "/game/enshrouded_server.exe"
  READ_LOGS_FILE = "/game/logs/enshrouded_server.log"
  XVFB_NEEDED    = "true"
}
```

Native Linux with arguments (Valheim):

```hcl
env {
  APP_ID      = "896660"
  EXE_PATH    = "/game/valheim_server.x86_64"
  SERVER_ARGS = "-nographics -batchmode -name MyServer -port 2456 -world Dedicated"
}
```

An exact build, so that a restart cannot bring in a patch you did not ask for:

```hcl
env {
  APP_ID      = "2278520"
  DEPOT_ID    = "2278521"
  MANIFEST_ID = "6823302667609042502"
  EXE_PATH    = "/game/enshrouded_server.exe"
}
```

## Details that matter

- **Saves are never touched.** DepotDownloader only deletes files that were in
  the previous manifest and are gone from the new one; `savegame/`, `logs/`
  and configuration have never been in a manifest.
- **Steam being down does not keep the server down.** If the update fails
  twice (the second time validating) and the game is installed, it starts the
  build on disk and says so in the log. `UPDATE_REQUIRED=true` restores the
  old behaviour of aborting.
- **Migrating an install made by steamcmd re-downloads nothing**: the first
  pass validates the disk against the manifest chunk by chunk (7.6 GB in 21 s
  on an OVH VPS) and fetches only what is missing.
- **There is no Steam client in here.** `steamclient.so` comes from Valve's
  redistributable (app 1007) and sits in `/opt/steam/linux{32,64}`, reachable
  through the usual `~/.steam/sdk32` and `~/.steam/sdk64`. GE-Proton is
  unpacked at `/opt/proton`, without its version in the path.
