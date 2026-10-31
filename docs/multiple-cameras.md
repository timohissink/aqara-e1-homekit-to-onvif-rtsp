# Multiple virtual cameras in one LXC

UniFi Protect identifies a camera by its MAC/IP, so every virtual ONVIF camera
needs its own network interface. The upstream onvif-server README uses
`macvlan` interfaces. Inside a Proxmox LXC it is cleaner to give the container
extra NICs (`net1`, `net2`, ...). Each one gets its own Proxmox-generated MAC,
is persistent, and is covered by the container firewall.

The multi-NIC procedure below is the supported setup for several cameras in
one LXC. It uses the standard Linux configuration for several interfaces in
one subnet, together with the upstream troubleshooting advice.

## Steps

1. On the Proxmox host, run `scripts/add-camera-nic.sh` for each extra camera:
   ```bash
   CTID=105 IDX=1 IP=192.168.1.32 PREFIX=24 NET=192.168.1.0/24 GW=192.168.1.1 ./scripts/add-camera-nic.sh
   CTID=105 IDX=2 IP=192.168.1.33 PREFIX=24 NET=192.168.1.0/24 GW=192.168.1.1 ./scripts/add-camera-nic.sh
   ```
   The script does three things:
   - adds `netX` with `firewall=1`;
   - sets `arp_ignore=1` / `arp_announce=2`, so each IP is answered only with
     its own MAC. Without this, Linux answers ARP for all IPs on every interface
     ("ARP flux"), and Protect sees every camera behind the same MAC;
   - adds a source-based routing table per interface, so replies leave through
     the interface that owns the address.
2. Reserve the IP for each new MAC in your DHCP server, or mark it as a fixed
   IP in UniFi Network. Use addresses outside the DHCP pool.
3. Add one block per MAC to `/etc/onvif-server/config.yaml`; see
   `onvif-server/config.yaml.example`. Every camera needs its own `uuid`. The
   ports may be the same (8081/8554), because each camera binds to its own IP.
4. Restart the service: `systemctl restart onvif-server`.
5. Check with `tools/onvif_test.sh <ip>` from a host that is allowed through the
   firewall. Each IP must report its own stream URI.
6. Check the MACs from another machine: `ip neigh | grep 192.168.1.3`. Every IP
   should have a different MAC.
