FROM debian:13-slim

ARG PROTON_VERSION
# DepotDownloader (SteamRE): sustituye a steamcmd para instalar y actualizar el
# juego. Binario self-contained (.NET dentro), sin runtime ni dependencias.
ARG DEPOTDOWNLOADER_VERSION=3.4.0
ARG DEPOTDOWNLOADER_SHA256=a999dec66b4850fc961bd50366696d23c2d0fad7b18790e6a5647b2f19097a53

ENV PROTON_VERSION=${PROTON_VERSION}

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
    && mkdir -p "/steamcmd/compatibilitytools.d" \
    # DepotDownloader en /opt/depotdownloader
    && mkdir -p /opt/depotdownloader \
    && curl -fsqL "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DEPOTDOWNLOADER_VERSION}/DepotDownloader-linux-x64.zip" -o /tmp/dd.zip \
    && echo "${DEPOTDOWNLOADER_SHA256}  /tmp/dd.zip" | sha256sum -c - \
    && python3 -c "import zipfile; zipfile.ZipFile('/tmp/dd.zip').extractall('/opt/depotdownloader')" \
    && rm -f /tmp/dd.zip \
    && chmod +x /opt/depotdownloader/DepotDownloader \
    && /opt/depotdownloader/DepotDownloader -V \
    # steamclient.so lo daba el propio steamcmd; ahora sale de la redist oficial
    # (app 1007, depot 1006), que es de donde Valve lo publica. Las rutas
    # /root/.steam/sdk{32,64} y STEAM_COMPAT_CLIENT_INSTALL_PATH no cambian:
    # Proton (lsteamclient) las busca ahí.
    # en la redist el de 64 bits va en linux64/ y el de 32 en la raíz
    && echo 'regex:^(steamclient.so|linux64/steamclient.so)$' > /tmp/sdk.txt \
    && /opt/depotdownloader/DepotDownloader -app 1007 -os linux -all-archs \
         -dir /steamcmd -filelist /tmp/sdk.txt \
    && mkdir -p /steamcmd/linux32 \
    && mv /steamcmd/steamclient.so /steamcmd/linux32/steamclient.so \
    && rm -f /tmp/sdk.txt \
    && rm -rf /steamcmd/.DepotDownloader \
    && test -s /steamcmd/linux64/steamclient.so \
    && test -s /steamcmd/linux32/steamclient.so \
    && mkdir -p /root/.steam \
    && ln -s /steamcmd/linux64 /root/.steam/sdk64 \
    && ln -s /root/.steam/sdk64/steamclient.so /root/.steam/sdk64/steamservice.so \
    && ln -s /steamcmd/linux32 /root/.steam/sdk32 \
    && ln -s /root/.steam/sdk32/steamclient.so /root/.steam/sdk32/steamservice.so \
    # Desde GE-Proton 11 el archivo lleva la arquitectura en el nombre (y en el
    # directorio que contiene); se prueba primero y se deja siempre en GE-Proton<versión>
    && cd /steamcmd/compatibilitytools.d \
    && { curl -fsqL "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${PROTON_VERSION}/GE-Proton${PROTON_VERSION}-x86_64.tar.gz" \
         || curl -fsqL "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${PROTON_VERSION}/GE-Proton${PROTON_VERSION}.tar.gz"; } | tar zxf - \
    && { [ -d "GE-Proton${PROTON_VERSION}" ] || mv "GE-Proton${PROTON_VERSION}-x86_64" "GE-Proton${PROTON_VERSION}"; } \
    && test -x "GE-Proton${PROTON_VERSION}/proton"

# Después de lo pesado, para que cambiar el entrypoint no rehaga la imagen entera
COPY ./rootfs/ /
RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
