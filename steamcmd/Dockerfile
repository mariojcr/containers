FROM debian:13-slim

RUN dpkg --add-architecture i386 \
    && apt update -y && apt install -y wget ca-certificates libc6-i686 lib32gcc-s1 \
    && mkdir /steamcmd && cd /steamcmd \
    && wget -nc https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz -O - | tar -zxv

ENTRYPOINT [ "/steamcmd/steamcmd.sh" ]
