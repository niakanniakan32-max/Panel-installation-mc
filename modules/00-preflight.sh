#!/bin/bash
# 00-preflight: root, OS, arch, resources.
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

[ "$(id -u)" -eq 0 ] || die "Run as root."
[ -f /etc/os-release ] || die "Cannot detect OS."
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}-${VERSION_ID:-}" in
  ubuntu-22.04|ubuntu-24.04) log "OS supported: $ID $VERSION_ID" ;;
  *) die "Unsupported OS: ${ID:-?} ${VERSION_ID:-?} (need Ubuntu 22.04 or 24.04)." ;;
esac
[ "$(uname -m)" = "x86_64" ] || die "Only x86_64 is supported."

MEM="$(total_mem_mb)"
if [ "$MEM" -lt 3500 ]; then
  warn "Only ${MEM} MB RAM detected. Big modpacks (RLCraft etc.) want 3 GB+ for a single server. Continue only for small servers."
fi
if [ -d "$PANEL_DIR" ]; then
  die "$PANEL_DIR already exists. Remove it or use another machine (fresh VPS required)."
fi
command -v curl >/dev/null || { apt-get update -y && apt-get install -y curl ca-certificates; }
log "Preflight OK."
