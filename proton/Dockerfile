# SPDX-FileCopyrightText: 2026 Mario Campos <https://github.com/mariojcr>
# SPDX-License-Identifier: Apache-2.0

FROM debian:13-slim

# The GE-Proton release to bundle. Single source of truth: Renovate updates it
# here and the workflow reads the image tag from it. The checksum is the one
# GloriousEggroll publishes next to the tarball, written by scripts/pin-proton.sh
# when the version moves.
ARG PROTON_VERSION=11-11
ARG PROTON_SHA512=45721a7b625b2404d8896bb5e2a8b87fc9623a394873a6dd6b900c839681d5c01ec694ca00d003fc9c733c5f6c5648af8171985656f9fa47e20999fbebdbe235

# DepotDownloader (SteamRE) installs and updates the game. It replaces
# steamcmd, which could report success without updating, needed the installed
# build's manifest kept around to avoid "Access Denied" on an anonymous login,
# and now and then left its validate task suspended for two minutes.
ARG DEPOTDOWNLOADER_VERSION=3.4.0
ARG DEPOTDOWNLOADER_SHA256=a999dec66b4850fc961bd50366696d23c2d0fad7b18790e6a5647b2f19097a53

# Proton wants a Steam client install to point at. This image is not one, but
# the Steam client libraries below are all it reads from it; the game's Wine
# prefix, the other half, goes in the game volume (see the entrypoint).
ENV PROTON_VERSION=${PROTON_VERSION} \
    STEAM_COMPAT_CLIENT_INSTALL_PATH=/opt/steam

RUN dpkg --add-architecture i386 \
    && apt update \
    && apt install --no-install-recommends -y \
        procps \
        ca-certificates \
        winbind \
        dbus \
        libfreetype6 \
        curl \
        jq \
        locales \
        xvfb \
        xauth \
        lib32gcc-s1 \
        python3 \
    && echo 'LANG="en_US.UTF-8"' > /etc/default/locale \
    && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen \
    && rm -f /etc/machine-id \
    && dbus-uuidgen --ensure=/etc/machine-id \
    && rm -rf /var/lib/apt/lists/* \
    && apt clean \
    && apt autoremove -y \
    # DepotDownloader: one self-contained binary, no .NET runtime to install
    && mkdir -p /opt/depotdownloader \
    && curl -fsqL "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DEPOTDOWNLOADER_VERSION}/DepotDownloader-linux-x64.zip" -o /tmp/dd.zip \
    && echo "${DEPOTDOWNLOADER_SHA256}  /tmp/dd.zip" | sha256sum -c - \
    && python3 -c "import zipfile; zipfile.ZipFile('/tmp/dd.zip').extractall('/opt/depotdownloader')" \
    && rm -f /tmp/dd.zip \
    && chmod +x /opt/depotdownloader/DepotDownloader \
    && /opt/depotdownloader/DepotDownloader -V \
    # steamclient.so comes from Valve's own redistributable (app 1007, depot
    # 1006): 64-bit under linux64/, 32-bit at the root. Games look it up
    # through ~/.steam/sdk{32,64}, so those stay where everyone expects them.
    && echo 'regex:^(steamclient.so|linux64/steamclient.so)$' > /tmp/sdk.txt \
    && /opt/depotdownloader/DepotDownloader -app 1007 -os linux -all-archs \
         -dir /opt/steam -filelist /tmp/sdk.txt \
    && mkdir -p /opt/steam/linux32 \
    && mv /opt/steam/steamclient.so /opt/steam/linux32/steamclient.so \
    && rm -f /tmp/sdk.txt \
    && rm -rf /opt/steam/.DepotDownloader \
    && test -s /opt/steam/linux64/steamclient.so \
    && test -s /opt/steam/linux32/steamclient.so \
    && mkdir -p /root/.steam \
    && ln -s /opt/steam/linux64 /root/.steam/sdk64 \
    && ln -s /root/.steam/sdk64/steamclient.so /root/.steam/sdk64/steamservice.so \
    && ln -s /opt/steam/linux32 /root/.steam/sdk32 \
    && ln -s /root/.steam/sdk32/steamclient.so /root/.steam/sdk32/steamservice.so \
    # some servers look for the client install through these two instead
    && ln -s /opt/steam /root/.steam/root \
    && ln -s /opt/steam /root/.steam/steam \
    # GE-Proton, without its version in the path: the entrypoint runs
    # /opt/proton/proton whichever release this is. Releases from 11 carry the
    # architecture in the file name; older ones do not.
    && { curl -fsqL -o /tmp/proton.tar.gz "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${PROTON_VERSION}/GE-Proton${PROTON_VERSION}-x86_64.tar.gz" \
         || curl -fsqL -o /tmp/proton.tar.gz "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${PROTON_VERSION}/GE-Proton${PROTON_VERSION}.tar.gz"; } \
    && echo "${PROTON_SHA512}  /tmp/proton.tar.gz" | sha512sum -c - \
    && mkdir -p /opt/proton \
    && tar xzf /tmp/proton.tar.gz -C /opt/proton --strip-components=1 \
    && rm -f /tmp/proton.tar.gz \
    && test -x /opt/proton/proton \
    && test -x /opt/proton/files/bin/wineserver

# Last, so that changing the entrypoint does not rebuild everything above
COPY ./rootfs/ /
RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
