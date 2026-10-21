#!/bin/sh
# SPDX-FileCopyrightText: 2026 Mario Campos <https://github.com/mariojcr>
# SPDX-License-Identifier: Apache-2.0
#
# Firewall for the allocation this sidecar shares a network namespace with,
# plus an optional port forwarded in through NAT-PMP.
set -euo pipefail

# -------- Configuration from the environment --------
FW_DNS="${FW_DNS:-}"                 # "DNS IP[,DNS IP2,...]"  omit = no DNS allowed
FW_EGRESS="${FW_EGRESS:-false}"      # "true"|"false"  omit = false
FW_ALLOW_IN="${FW_ALLOW_IN:-}"       # "SRC:PROTO[:PORT]"  PORT: 443 | 8000-9000 | omit = any
FW_ALLOW_OUT="${FW_ALLOW_OUT:-}"     # "DST:PROTO[:PORT]"  PORT: 443 | 8000-9000 | omit = any

# NAT-PMP (ProtonVPN port forwarding)
NATPMP_ENABLED="${NATPMP_ENABLED:-false}"     # "true" = ask for a forwarded port
NATPMP_GATEWAY="${NATPMP_GATEWAY:-10.2.0.1}" # NAT-PMP gateway IP (ProtonVPN default)
NATPMP_INTERVAL="${NATPMP_INTERVAL:-45}"     # seconds between renewals (lifetime=60)

# -------- Helpers --------
trim() { awk '{$1=$1};1'; }

# -------- NAT-PMP loop --------
natpmp_loop() {
  echo "[natpmp] starting loop (gateway=$NATPMP_GATEWAY interval=${NATPMP_INTERVAL}s)"

  # wait for the NAT-PMP gateway to answer (backoff: 5s, 10s, 20s, 30s...)
  wait=5
  while ! natpmpc -g "$NATPMP_GATEWAY" >/dev/null 2>&1; do
    echo "[natpmp] gateway $NATPMP_GATEWAY unavailable, retrying in ${wait}s..."
    sleep "$wait"
    [ "$wait" -lt 30 ] && wait=$((wait * 2))
  done
  echo "[natpmp] gateway $NATPMP_GATEWAY reachable"

  prev_port=""
  while true; do
    # ask for a UDP + TCP mapping with a 60s lifetime
    udp_out="$(natpmpc -a 1 0 udp 60 -g "$NATPMP_GATEWAY" 2>&1)" || {
      echo "[natpmp] ERROR: natpmpc UDP failed"; echo "$udp_out"
      sleep "$NATPMP_INTERVAL"; continue
    }
    natpmpc -a 1 0 tcp 60 -g "$NATPMP_GATEWAY" >/dev/null 2>&1 || {
      echo "[natpmp] ERROR: natpmpc TCP failed"
      sleep "$NATPMP_INTERVAL"; continue
    }

    port="$(echo "$udp_out" | awk '/Mapped public port/{print $4}')"
    if [ -n "$port" ]; then
      if [ "$port" != "$prev_port" ]; then
        # close the previous port
        if [ -n "$prev_port" ]; then
          iptables -D INPUT -i "$IFACE" -p tcp --dport "$prev_port" -j ACCEPT 2>/dev/null || true
          iptables -D INPUT -i "$IFACE" -p udp --dport "$prev_port" -j ACCEPT 2>/dev/null || true
        fi
        # open the new one
        iptables -A INPUT -i "$IFACE" -p tcp --dport "$port" -j ACCEPT
        iptables -A INPUT -i "$IFACE" -p udp --dport "$port" -j ACCEPT
        echo "[natpmp] port assigned: $port (UDP+TCP) — INPUT rule updated"
        iptables -S || true
        prev_port="$port"
      fi
    else
      echo "[natpmp] WARNING: could not parse the port"
      echo "$udp_out"
    fi

    sleep "$NATPMP_INTERVAL"
  done
}

# -------- Interface --------
IFACE="$(ip -4 -o addr show | awk '!/ lo /{print $2; exit}')"
ALLOC_CIDR="$(ip -4 -o addr show dev "$IFACE" | awk '{print $4}' || true)"
ALLOC_IP="$(echo "$ALLOC_CIDR" | cut -d/ -f1)"

# -------- iptables (nf_tables) --------
# flush whatever is there
iptables -F INPUT || true
iptables -F OUTPUT || true
iptables -F FORWARD || true
iptables -X || true

# base policies
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# established / loopback / ICMP
iptables -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT  -p icmp -j ACCEPT
iptables -A OUTPUT -p icmp -j ACCEPT

# DNS (UDP/TCP 53)
IFS=','; for d in $FW_DNS; do
  d="$(echo "$d" | trim)"; [ -n "$d" ] || continue
  iptables -A OUTPUT -p udp -d "$d" --dport 53 -j ACCEPT
  iptables -A OUTPUT -p tcp -d "$d" --dport 53 -j ACCEPT
done; unset IFS

# full egress when asked for
[ "${FW_EGRESS}" = "true" ] && iptables -A OUTPUT -j ACCEPT

# Allow IN
IFS=','; for r in $FW_ALLOW_IN; do
  r="$(echo "$r" | trim)"; [ -n "$r" ] || continue
  SRC="$(echo "$r" | cut -d: -f1)"
  PROTO="$(echo "$r" | cut -d: -f2)"; [ -n "$PROTO" ] || PROTO="tcp"
  PORT="$(echo "$r" | cut -d: -f3 | tr '-' ':')"
  if [ -n "$PORT" ]; then
    iptables -A INPUT -p "$PROTO" -s "$SRC" --dport "$PORT" -j ACCEPT
  else
    iptables -A INPUT -p "$PROTO" -s "$SRC" -j ACCEPT
  fi
done; unset IFS

# Allow OUT
IFS=','; for r in $FW_ALLOW_OUT; do
  r="$(echo "$r" | trim)"; [ -n "$r" ] || continue
  DST="$(echo "$r" | cut -d: -f1)"
  PROTO="$(echo "$r" | cut -d: -f2)"; [ -n "$PROTO" ] || PROTO="tcp"
  PORT="$(echo "$r" | cut -d: -f3 | tr '-' ':')"
  if [ -n "$PORT" ]; then
    iptables -A OUTPUT -p "$PROTO" -d "$DST" --dport "$PORT" -j ACCEPT
  else
    iptables -A OUTPUT -p "$PROTO" -d "$DST" -j ACCEPT
  fi
done; unset IFS

echo "[fw] iface=$IFACE ip=$ALLOC_IP egress=$FW_EGRESS"
echo "[fw] DNS=$FW_DNS"
echo "[fw] allow_in=$FW_ALLOW_IN"
echo "[fw] allow_out=$FW_ALLOW_OUT"
echo "[fw] natpmp=$NATPMP_ENABLED"

iptables -S || true

# -------- NAT-PMP --------
if [ "$NATPMP_ENABLED" = "true" ]; then
  natpmp_loop &
  NATPMP_PID=$!
  echo "[natpmp] loop started (PID=$NATPMP_PID)"
fi

# wait for a signal
trap 'echo "[fw] signal received, exiting..."; [ -n "${NATPMP_PID:-}" ] && kill $NATPMP_PID 2>/dev/null; exit 0' INT TERM

sleep infinity &
wait $!
