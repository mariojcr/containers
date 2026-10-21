#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mario Campos <https://github.com/mariojcr>
# SPDX-License-Identifier: Apache-2.0
#
# Renovate runs this when it bumps DEPOTDOWNLOADER_VERSION: it downloads that
# release's zip and writes its sha256 into the Dockerfile. If it never runs,
# the build fails on the checksum, which is the failure we want — an
# unverified binary is not installed.
set -euo pipefail

version="${1:?missing DepotDownloader version}"
dockerfile="${2:-proton/Dockerfile}"

# the version ends up in a URL and in a sed expression: keep it to digits
[[ "${version}" =~ ^[0-9]+(\.[0-9]+)*$ ]] \
  || { echo "suspicious version: ${version}" >&2; exit 1; }

url="https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${version}/DepotDownloader-linux-x64.zip"
tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
curl -fsSL --retry 3 -o "${tmp}" "${url}"
sha="$(sha256sum "${tmp}" | cut -d' ' -f1)"

sed -i -E "s|^ARG DEPOTDOWNLOADER_SHA256=.*|ARG DEPOTDOWNLOADER_SHA256=${sha}|" "${dockerfile}"
grep -q "^ARG DEPOTDOWNLOADER_SHA256=${sha}$" "${dockerfile}" \
  || { echo "could not write the sha256 into ${dockerfile}" >&2; exit 1; }
echo "DepotDownloader ${version}: ${sha}"
