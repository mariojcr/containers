# SPDX-FileCopyrightText: 2026 Mario Campos <https://github.com/mariojcr>
# SPDX-License-Identifier: Apache-2.0
# Network sidecar for Nomad tasks: it sets up the firewall in the allocation's
# network namespace and, on request, keeps a port open through NAT-PMP.
FROM alpine:3.24

RUN apk add --no-cache iptables nftables iproute2 libnatpmp

COPY ./rootfs/ /

ENTRYPOINT [ "/entrypoint.sh" ]
