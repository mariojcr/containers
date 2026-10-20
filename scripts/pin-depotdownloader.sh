#!/usr/bin/env bash
# Renovate llama a esto cuando sube DEPOTDOWNLOADER_VERSION: baja el zip de esa
# versión y escribe su sha256 en el Dockerfile. Si no llegara a ejecutarse, la
# build falla al comprobar el hash, que es el fallo que queremos (nunca
# instalar un binario sin verificar).
set -euo pipefail

version="${1:?falta la versión de DepotDownloader}"
dockerfile="${2:-proton/Dockerfile}"

# la versión acaba en una URL y en un sed: que sea lo que decimos que es
[[ "${version}" =~ ^[0-9]+(\.[0-9]+)*$ ]] \
  || { echo "versión con formato raro: ${version}" >&2; exit 1; }
url="https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${version}/DepotDownloader-linux-x64.zip"

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
curl -fsSL --retry 3 -o "${tmp}" "${url}"
sha="$(sha256sum "${tmp}" | cut -d' ' -f1)"

sed -i -E "s|^ARG DEPOTDOWNLOADER_SHA256=.*|ARG DEPOTDOWNLOADER_SHA256=${sha}|" "${dockerfile}"
grep -q "^ARG DEPOTDOWNLOADER_SHA256=${sha}$" "${dockerfile}" \
  || { echo "no se pudo escribir el sha256 en ${dockerfile}" >&2; exit 1; }
echo "DepotDownloader ${version}: ${sha}"
