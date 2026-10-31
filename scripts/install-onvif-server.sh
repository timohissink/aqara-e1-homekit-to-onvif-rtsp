#!/usr/bin/env bash
# Run INSIDE the Debian 13 LXC (as root).
# Installs daniela-hase/onvif-server pinned to a known-good commit and runs it
# as an unprivileged systemd service.
set -euo pipefail

REPO="https://github.com/daniela-hase/onvif-server.git"
COMMIT="${ONVIF_SERVER_COMMIT:-7aa2c541b67b1a2760887a1706d7a5e45e5ae1a4}"  # tested 2026-10
DIR=/opt/onvif-server
CONF_DIR=/etc/onvif-server

apt-get update
apt-get -y full-upgrade
apt-get -y install --no-install-recommends nodejs npm git ca-certificates ffmpeg

node -v   # Debian 13 ships Node.js 20.x, upstream needs >= 16

if [ ! -d "$DIR/.git" ]; then
  git clone "$REPO" "$DIR"
fi
git -C "$DIR" fetch --all --quiet
git -C "$DIR" checkout --quiet "$COMMIT"
(cd "$DIR" && npm install --omit=dev --no-audit --no-fund)
chown -R root:root "$DIR"

id onvif >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin onvif

install -d -m 0755 "$CONF_DIR"
if [ ! -f "$CONF_DIR/config.yaml" ]; then
  echo "Put your config in $CONF_DIR/config.yaml (see onvif-server/config.yaml.example), then:"
  echo "  systemctl enable --now onvif-server"
fi
chmod 0644 "$CONF_DIR"/config.yaml 2>/dev/null || true

cat > /etc/systemd/system/onvif-server.service <<'UNIT'
[Unit]
Description=Virtual ONVIF server for UniFi Protect (daniela-hase/onvif-server)
After=network-online.target
Wants=network-online.target

[Service]
User=onvif
Group=onvif
WorkingDirectory=/opt/onvif-server
ExecStart=/usr/bin/node /opt/onvif-server/main.js /etc/onvif-server/config.yaml
Restart=always
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadOnlyPaths=/etc/onvif-server

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload

# Optional hardening: nothing else needs to listen in this container.
systemctl disable --now ssh.socket ssh.service postfix.service 2>/dev/null || true

if [ -f "$CONF_DIR/config.yaml" ]; then
  systemctl enable --now onvif-server
  sleep 3
  systemctl --no-pager status onvif-server | head -15
fi
