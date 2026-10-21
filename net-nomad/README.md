<!--
SPDX-FileCopyrightText: 2026 Mario Campos <https://github.com/mariojcr>
SPDX-License-Identifier: Apache-2.0
-->

# net-nomad

A network sidecar for a Nomad task: it runs before the service, in the same
network namespace, and leaves the allocation's firewall in place. On request
it also keeps a port open from the outside through NAT-PMP (ProtonVPN's port
forwarding).

`ghcr.io/mariojcr/net-nomad:1.0.0`, plus `…:1.0.0-<short sha>` to pin an exact
build.

It needs `NET_ADMIN` and the network namespace of the task it protects — in
Nomad, a task with `lifecycle { hook = "prestart" }` in the same group.

## Variables

| Variable | Default | What for |
|---|---|---|
| `FW_DNS` | — | DNS addresses allowed out (53/udp and 53/tcp), comma separated. Without it there is no DNS |
| `FW_EGRESS` | `false` | `true` allows all outbound traffic |
| `FW_ALLOW_IN` | — | Inbound rules, `SOURCE:PROTO[:PORT]`, comma separated. The port may be a range (`8000-9000`); without one, any port |
| `FW_ALLOW_OUT` | — | The same outbound: `DESTINATION:PROTO[:PORT]` |
| `NATPMP_ENABLED` | `false` | `true` asks for a forwarded port and renews it |
| `NATPMP_GATEWAY` | `10.2.0.1` | The NAT-PMP gateway (ProtonVPN's by default) |
| `NATPMP_INTERVAL` | `45` | Seconds between renewals (the mapping lasts 60) |

The base policy is `DROP` on INPUT, OUTPUT and FORWARD; loopback, ICMP and
established traffic are always allowed. When NAT-PMP hands out a new port, the
rule for the previous one is removed and the new one is opened, TCP and UDP.

## Example

```hcl
task "network-rules" {
  driver = "podman"
  lifecycle {
    hook    = "prestart"
    sidecar = true
  }
  config {
    image   = "ghcr.io/mariojcr/net-nomad:1.0.0"
    cap_add = ["NET_ADMIN"]
  }
  env {
    FW_DNS       = "192.168.0.1"
    FW_ALLOW_IN  = "192.168.0.0/24:tcp:443"
    FW_ALLOW_OUT = "0.0.0.0/0:tcp:443"
  }
}
```
