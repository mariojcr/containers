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

Renovate corre los lunes (`.github/workflows/renovate.yml`) y abre una PR por
cada versión nueva de:

- las imágenes base de los `Dockerfile` y las actions de los workflows, con
  sus managers nativos;
- **DepotDownloader**, que es un `ARG` del Dockerfile de proton. Al subirlo,
  un `postUpgradeTask` ejecuta `scripts/pin-depotdownloader.sh`, que baja el
  zip nuevo y reescribe su `sha256` en el Dockerfile. Si eso no corriera, la
  build falla al comprobar el hash, que es el fallo correcto;
- **GE-Proton**, cuya versión vive en el workflow porque es a la vez
  build-arg y tag. Sus releases se llaman `GE-Proton11-7`, así que el orden
  se define con un `versioning` propio en `renovate.json5`.

Renovate usa el `GITHUB_TOKEN` por defecto, y las PR que abre así **no**
disparan la build (protección de GitHub contra bucles). Para que cada subida
se valide construyendo, hay que poner un PAT en el secret `RENOVATE_TOKEN`.
