FROM ghcr.io/elmariovi/debian:trixie-slim

ARG UID=1000

RUN dpkg --add-architecture i386 \
    && install_packages wget ca-certificates libc6-i686 lib32gcc-s1 \
    && mkdir /steamcmd && cd /steamcmd \
    && wget -nc https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz -O - | tar -zxv \
    && adduser --system --group --uid ${UID} --disabled-login --home /steamcmd limmo \
    && chown limmo:limmo /steamcmd -R

USER limmo

ENTRYPOINT [ "/steamcmd/steamcmd.sh" ]
