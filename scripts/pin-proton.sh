#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mario Campos <https://github.com/mariojcr>
# SPDX-License-Identifier: Apache-2.0
#
# Renovate runs this when it bumps PROTON_VERSION. GloriousEggroll publishes a
# .sha512sum next to each tarball, so this reads that small file instead of
# downloading half a gigabyte, and writes the checksum into the Dockerfile.
# It travels the same way as the tarball, so it proves the download arrived
# whole rather than that nobody replaced both; what it buys is a value under
# review in git, and a build that fails loudly if the artifact ever changes.
set -euo pipefail

version="${1:?missing GE-Proton version}"
dockerfile="${2:-proton/Dockerfile}"

[[ "${version}" =~ ^[0-9]+-[0-9]+$ ]] \
  || { echo "suspicious version: ${version}" >&2; exit 1; }

base="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${version}"
# releases from 11 carry the architecture in the file name, older ones do not
line="$(curl -fsSL --retry 3 "${base}/GE-Proton${version}-x86_64.sha512sum" \
        || curl -fsSL --retry 3 "${base}/GE-Proton${version}.sha512sum")"
sha="$(echo "${line}" | awk '{print $1}')"

[[ "${sha}" =~ ^[0-9a-f]{128}$ ]] \
  || { echo "that does not look like a sha512: ${sha}" >&2; exit 1; }

sed -i -E "s|^ARG PROTON_SHA512=.*|ARG PROTON_SHA512=${sha}|" "${dockerfile}"
grep -q "^ARG PROTON_SHA512=${sha}$" "${dockerfile}" \
  || { echo "could not write the sha512 into ${dockerfile}" >&2; exit 1; }
echo "GE-Proton ${version}: ${sha}"
