# net-nomad

Sidecar de red para una tarea de Nomad: corre antes que el servicio, en el
mismo namespace de red, y deja montado el cortafuegos de la asignación. Si se
le pide, mantiene además un puerto abierto hacia fuera por NAT-PMP (el
port forwarding de ProtonVPN).

`ghcr.io/mariojcr/net-nomad:1.0.0`, y `…:1.0.0-<sha>` para fijar una build concreta

Necesita `NET_ADMIN` y compartir el namespace de red con la tarea que protege
(en Nomad, un `task` con `lifecycle { hook = "prestart" }` dentro del mismo
grupo).

## Variables

| Variable | Por defecto | Para qué |
|---|---|---|
| `FW_DNS` | — | IPs de DNS a las que se permite salir (53/udp y 53/tcp), separadas por comas. Sin esto, no hay DNS |
| `FW_EGRESS` | `false` | `true` permite toda la salida |
| `FW_ALLOW_IN` | — | Reglas de entrada `ORIGEN:PROTO[:PUERTO]`, separadas por comas. El puerto admite rango (`8000-9000`); sin puerto, todos |
| `FW_ALLOW_OUT` | — | Lo mismo para salida: `DESTINO:PROTO[:PUERTO]` |
| `NATPMP_ENABLED` | `false` | `true` pide puerto por NAT-PMP y lo renueva |
| `NATPMP_GATEWAY` | `10.2.0.1` | El gateway NAT-PMP (por defecto el de ProtonVPN) |
| `NATPMP_INTERVAL` | `45` | Segundos entre renovaciones (el mapeo dura 60) |

La política base es `DROP` en INPUT, OUTPUT y FORWARD; se permiten siempre
loopback, ICMP y lo ya establecido. Cuando NAT-PMP asigna un puerto nuevo, la
regla del anterior se retira y se abre la del nuevo (TCP y UDP).

## Ejemplo

```hcl
task "network-rules" {
  driver = "podman"
  lifecycle {
    hook    = "prestart"
    sidecar = true
  }
  config {
    image      = "ghcr.io/mariojcr/net-nomad:1.0.0"
    cap_add    = ["NET_ADMIN"]
  }
  env {
    FW_DNS       = "192.168.0.1"
    FW_ALLOW_IN  = "192.168.0.0/24:tcp:443"
    FW_ALLOW_OUT = "0.0.0.0/0:tcp:443"
  }
}
```
