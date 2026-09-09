#!/bin/bash
# 50-wings: daemon binary + systemd service (enabled, not started - configured in 60-node).
set -euo pipefail
source "$(dirname "$0")/common.sh"

if [ -f /usr/local/bin/wings ]; then
  log "Wings binary already present."
else
  log "Downloading Wings (latest)..."
  mkdir -p /etc/pterodactyl /var/run/wings
  ARCH="$(dpkg --print-architecture)"
  case "$ARCH" in
    amd64) WINGS_ARCH="amd64" ;;
    arm64) WINGS_ARCH="arm64" ;;
    *) die "Unsupported architecture for Wings: $ARCH" ;;
  esac
  curl -fsSL --retry 3 --retry-delay 5 --retry-all-errors --max-time 300 -o /usr/local/bin/wings \
    "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$WINGS_ARCH"
  chmod u+x /usr/local/bin/wings
fi

log "Installing wings systemd service..."
cat > /etc/systemd/system/wings.service <<'UNIT'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable wings
log "Wings installed (will be started after configuration)."
