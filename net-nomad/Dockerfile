# Sidecar de red para tareas de Nomad: monta el cortafuegos en el namespace de
# la asignación y, si se pide, pide un puerto hacia fuera por NAT-PMP.
FROM alpine:3.24

RUN apk add --no-cache iptables nftables iproute2 libnatpmp

COPY ./rootfs/ /

ENTRYPOINT [ "/entrypoint.sh" ]
