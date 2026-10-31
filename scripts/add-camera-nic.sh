#!/usr/bin/env bash
# Run on the Proxmox host (as root). Adds an extra NIC (= extra MAC + IP) to the
# onvif LXC for an additional virtual camera, and installs the ARP/routing
# settings needed when several interfaces of one host are in the same subnet.
#
# Usage: CTID=105 IDX=1 IP=192.168.1.32 PREFIX=24 NET=192.168.1.0/24 GW=192.168.1.1 ./add-camera-nic.sh
# See docs/multiple-cameras.md for the full multi-camera setup.
set -euo pipefail
CTID="${CTID:?}"; IDX="${IDX:?1,2,...}"; IP="${IP:?}"; PREFIX="${PREFIX:-24}"; GW="${GW:?}"; NET="${NET:?network in CIDR, e.g. 192.168.1.0/24}"
BRIDGE="${BRIDGE:-vmbr0}"

pct set "$CTID" --net"$IDX" "name=eth$IDX,bridge=$BRIDGE,ip=$IP/$PREFIX,firewall=1"
pct config "$CTID" | grep "^net$IDX:" | grep -o 'hwaddr=[^,]*'

pct exec "$CTID" -- bash -s "$IDX" "$IP" "$PREFIX" "$GW" "$NET" <<'INNER'
set -euo pipefail
IDX="$1"; IP="$2"; PREFIX="$3"; GW="$4"; NET="$5"; DEV="eth$IDX"; TABLE=$((100+IDX))
# Answer ARP only for the address configured on the receiving interface,
# so Protect sees the right MAC for every IP.
cat > /etc/sysctl.d/90-onvif-multi-nic.conf <<SYS
net.ipv4.conf.all.arp_ignore=1
net.ipv4.conf.all.arp_announce=2
net.ipv4.conf.all.rp_filter=2
SYS
sysctl --system >/dev/null
# Source-based routing: replies from $IP leave via $DEV.
cat > /etc/network/if-up.d/onvif-$DEV <<HOOK
#!/bin/sh
[ "\$IFACE" = "$DEV" ] || exit 0
ip route replace $NET dev $DEV src $IP table $TABLE 2>/dev/null || true
ip route replace default via $GW dev $DEV table $TABLE
ip rule del from $IP table $TABLE 2>/dev/null || true
ip rule add from $IP table $TABLE
HOOK
chmod +x /etc/network/if-up.d/onvif-$DEV
IFACE="$DEV" /etc/network/if-up.d/onvif-$DEV
ip -br addr show "$DEV"
INNER
echo "Now add a block with this MAC to /etc/onvif-server/config.yaml and restart onvif-server."
