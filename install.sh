#!/bin/bash
#
# One-link panel installer (Jexpanel/Everest + Wings + modpack browser)
# Usage:
#   bash <(curl -sL https://raw.githubusercontent.com/niakanniakan32-max/Panel-installation-mc/main/install.sh)
#
# Optional env vars for unattended installs (all have interactive prompts otherwise):
#   DOMAIN EMAIL ADMIN_USER ADMIN_PASS TIMEZONE HTTP_PORT HTTPS_PORT WINGS_PORT SFTP_PORT
#   NODE_NAME NODE_MEM NODE_DISK NODE_CPU PORT_START PORT_COUNT JEXPANEL_VERSION
# Flags: --dry-run (print plan only) --non-interactive --help
#
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/niakanniakan32-max/Panel-installation-mc/main}"
JEXPANEL_VERSION="${JEXPANEL_VERSION:-v4.0.7}"
PANEL_DIR="/var/www/jexpanel"
LOG="/var/log/panel-install.log"

DRY_RUN=0
NON_INTERACTIVE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --non-interactive) NON_INTERACTIVE=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $arg (see --help)"; exit 1 ;;
  esac
done

mkdir -p "$(dirname "$LOG")"
touch "$LOG"

MODULES="00-preflight 10-prompt 20-deps 30-panel 40-nginx 50-wings 60-node 70-eggs 80-modpacks 90-finish"

if [ "$DRY_RUN" = "1" ]; then
  echo "DRY RUN - this installer would execute, in order:"
  echo "  preflight checks (root, Ubuntu 22.04/24.04, RAM)"
  echo "  interactive prompts (domain, email, admin, timezone, ports with x-ui warnings, node sizing)"
  echo "  install: apt deps, PHP 8.5, composer, MariaDB, nginx, Redis, Docker, Node.js 22, certbot"
  echo "  panel: Jexpanel $JEXPANEL_VERSION -> $PANEL_DIR, DB, admin user, setup wizard skipped"
  echo "  nginx: port-80 ACME block + panel vhost, Let's Encrypt via webroot"
  echo "  wings: binary + systemd service (not started until configured)"
  echo "  node: location-less node + allocations via panel DB, wings config.yml, wings started"
  echo "  eggs: Modrinth Generic egg (POSIX installer, CurseForge/FTB/manual support)"
  echo "  modpacks: CurseForge + FTB + upload endpoints, /browse page, popup picker, frontend build"
  echo "  finish: verify panel+wings, print URL + credentials (/root/panel-credentials.env)"
  echo ""
  echo "Modules that would be fetched from: $REPO_RAW/{lib,modules,files}/..."
  exit 0
fi

export REPO_RAW JEXPANEL_VERSION PANEL_DIR LOG NON_INTERACTIVE TMPDIR_WORK
export DOMAIN="${DOMAIN:-}" EMAIL="${EMAIL:-}" ADMIN_USER="${ADMIN_USER:-}"
export ADMIN_PASS="${ADMIN_PASS:-}" TIMEZONE="${TIMEZONE:-}"
export HTTP_PORT="${HTTP_PORT:-}" HTTPS_PORT="${HTTPS_PORT:-}"
export WINGS_PORT="${WINGS_PORT:-}" SFTP_PORT="${SFTP_PORT:-}"
export NODE_NAME="${NODE_NAME:-}" NODE_MEM="${NODE_MEM:-}" NODE_DISK="${NODE_DISK:-}" NODE_CPU="${NODE_CPU:-}"
export PORT_START="${PORT_START:-}" PORT_COUNT="${PORT_COUNT:-}"

TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT
# tinker/sudo steps run as www-data and must read files from the workdir.
chmod 755 "$TMPDIR_WORK"

# Bootstrap: minimal images (docker ubuntu, fresh VPS templates) may lack curl.
if ! command -v curl >/dev/null 2>&1; then
  echo "* Installing curl for bootstrap..."
  apt-get update -y && apt-get install -y curl ca-certificates
fi

fetch() { # (also defined in lib/common.sh for modules)
  curl -fsSL "$REPO_RAW/$1" -o "$2"
}

fetch "lib/common.sh" "$TMPDIR_WORK/common.sh"
# shellcheck source=lib/common.sh
source "$TMPDIR_WORK/common.sh"

for mod in $MODULES; do
  fetch "modules/$mod.sh" "$TMPDIR_WORK/$mod.sh"
  log "===== module: $mod ====="
  bash "$TMPDIR_WORK/$mod.sh" 2>&1 | tee -a "$LOG"
done

log "Installer finished. Details in $LOG"
