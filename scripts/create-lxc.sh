#!/usr/bin/env bash
# Run on the Proxmox host (as root). Creates an unprivileged Debian 13 LXC for
# onvif-server with one NIC (one virtual camera). Add more NICs later with
# scripts/add-camera-nic.sh.
#
# Usage: CTID=105 IP=192.168.1.31/24 GW=192.168.1.1 ./create-lxc.sh
set -euo pipefail

CTID="${CTID:?set CTID, e.g. 105}"
IP="${IP:?set IP in CIDR notation, e.g. 192.168.1.31/24}"
GW="${GW:?set GW, e.g. 192.168.1.1}"
HOSTNAME="${HOSTNAME_CT:-onvif01}"
BRIDGE="${BRIDGE:-vmbr0}"
STORAGE="${STORAGE:-local-lvm}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"

pveam update >/dev/null
TEMPLATE="$(pveam available --section system | awk '/debian-13-standard/ {print $2}' | sort -V | tail -1)"
[ -n "$TEMPLATE" ] || { echo "No Debian 13 template found"; exit 1; }
pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE" || pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"

pct create "$CTID" "$TEMPLATE_STORAGE:vztmpl/$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --unprivileged 1 --features nesting=1 \
  --cores 1 --memory 512 --swap 256 \
  --rootfs "$STORAGE:4" \
  --net0 "name=eth0,bridge=$BRIDGE,ip=$IP,gw=$GW,firewall=1" \
  --nameserver "$GW" \
  --onboot 1 \
  --description "Virtual ONVIF camera(s) for UniFi Protect (daniela-hase/onvif-server) -> go2rtc"

pct start "$CTID"
echo "CT $CTID created. MAC of eth0 (create a DHCP reservation / fixed IP for it):"
pct config "$CTID" | grep -o 'hwaddr=[^,]*'
echo "Next: pct push $CTID scripts/install-onvif-server.sh /root/install-onvif-server.sh && pct exec $CTID -- bash /root/install-onvif-server.sh"
