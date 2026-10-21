# containers

Imágenes pequeñas que usa el clúster de casa, cada una en su directorio y con
su workflow. Se publican en `ghcr.io/mariojcr/<imagen>`.

| Imagen | Qué es |
|---|---|
| [`proton`](proton/) | Servidores dedicados de Steam: DepotDownloader + GE-Proton, para binarios de Windows o nativos |
| [`net-nomad`](net-nomad/) | Sidecar de red para tareas de Nomad: cortafuegos de la asignación y NAT-PMP |

## Cómo se construyen

Cada imagen tiene un workflow en `.github/workflows/<imagen>.yml` que entra
cuando cambia su directorio (o el propio workflow, que es donde vive la
versión en el caso de proton). Las PR solo comprueban que construye; publican
únicamente los push a una rama.

## Actualizaciones de dependencias

Dos bots, cada uno con lo que sabe hacer, y ninguna credencial que guardar.

**Dependabot** (`.github/dependabot.yml`) lleva las imágenes base de los
Dockerfile y las actions de los workflows. Es nativo de GitHub: no necesita
token, puede escribir en `.github/workflows/` y sus PR sí disparan la build,
así que la subida se valida antes de entrar.

**Renovate** (`renovate.json5`, los lunes desde su propio workflow) lleva lo
que Dependabot no sabe leer, que son versiones sueltas dentro de ficheros:

- **GE-Proton**, el `ARG PROTON_VERSION` del Dockerfile de proton, de donde el
  workflow saca también el tag de la imagen. Sus releases se llaman
  `GE-Proton11-7`, así que el orden se define con un `versioning` propio.
- **DepotDownloader**, su `ARG` hermano. Al subirlo, un `postUpgradeTask`
  ejecuta `scripts/pin-depotdownloader.sh`, que baja el zip nuevo y reescribe
  su `sha256`. Si eso no corriera, la build falla al comprobar el hash, que es
  el fallo correcto.

Renovate corre con el `GITHUB_TOKEN` de Actions, que tiene dos límites: no
puede escribir en `.github/workflows/` (por eso las versiones viven en los
Dockerfile y las actions son cosa de Dependabot) y sus PR **no** disparan
otros workflows. Es decir, una subida de GE-Proton se valida al entrar en
`main`, no en la PR; si la build falla, el tag publicado se queda como estaba.
Para que también se valide en la PR, habría que cambiar el token por una app
de GitHub propia (`actions/create-github-app-token`), que es la única forma de
tener las dos cosas sin un token personal.

Para que Renovate pueda abrir PR, este repo tiene activado "Allow GitHub
Actions to create and approve pull requests".
