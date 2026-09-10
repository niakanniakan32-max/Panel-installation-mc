#!/bin/bash
# 10-prompt: gather all answers up front (or honor env vars / --non-interactive).
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo ""
echo "=== Panel setup ==="
ask DOMAIN "Panel domain (FQDN, e.g. panel.example.com)" ""
[ -n "$DOMAIN" ] || die "Domain is required (needed for nginx + SSL)."
ask EMAIL "Email for Let's Encrypt + admin account" "admin@$DOMAIN"
ask ADMIN_USER "Admin username" "admin"
if [ -z "${ADMIN_PASS:-}" ] && [ "${NON_INTERACTIVE:-0}" != "1" ]; then
  printf "* Admin password (empty = auto-generate): "
  read -r -s ADMIN_PASS || true
  echo ""
fi
if [ -z "${ADMIN_PASS:-}" ]; then
  ADMIN_PASS="$(gen_pass 16)"
  log "Generated admin password (shown again at the end)."
fi
ask TIMEZONE "Timezone" "UTC"

echo ""
echo "=== Ports (with recommendations) ==="
show_port_table
ask_port HTTPS_PORT "Panel HTTPS port" "8443" \
  "Recommended 8443: safe alongside x-ui/VPN tools. Port 443 is standard but very often already taken (x-ui uses 443)."
ask_port HTTP_PORT "Panel HTTP port (redirects to HTTPS)" "8081" \
  "Recommended 8081: x-ui commonly uses 8080. Port 80 is still used automatically for Let's Encrypt checks."
ask_port WINGS_PORT "Wings daemon port" "8444" \
  "Recommended 8444: any free high port. Never 443/8080 (x-ui)."
ask_port SFTP_PORT "Wings SFTP port" "2022" \
  "Recommended 2022: never 22 (SSH)."

echo ""
echo "=== Node (this machine) ==="
ask NODE_NAME "Node name" "node1"
DEF_MEM=$(( $(total_mem_mb) * 90 / 100 ))
ask NODE_MEM "Node RAM in MB" "$DEF_MEM"
ask NODE_DISK "Node disk in MB" "20480"
ask NODE_CPU "Node CPU in % (100 = 1 core)" "200"
# Public IP: detect, show it, confirm it; fall back to manual entry.
# (Auto-detection can be wrong behind NAT/proxies, and IP services can fail.)
MANUAL_IP=0
while true; do
  if [ "$MANUAL_IP" = "0" ] && [ -z "${PUBIP:-}" ]; then
    PUBIP="$(detect_pubip || true)"
    if [ -z "$PUBIP" ]; then
      warn "All IP detection services failed (ipify, cloudflare, icanhazip, amazon, ifconfig.me)."
    fi
  fi
  if [ -n "${PUBIP:-}" ] && valid_ip "$PUBIP"; then
    if [ "${NON_INTERACTIVE:-0}" = "1" ]; then
      log "Using public IP: $PUBIP"
      break
    fi
    echo "* Detected public IP: $PUBIP"
    printf "* Is this correct? [Y/n]: "
    read -r ip_ok || true
    case "$ip_ok" in
      [nN]*) PUBIP=""; MANUAL_IP=1; continue ;;
      *) log "Using public IP: $PUBIP"; break ;;
    esac
  fi
  if [ "${NON_INTERACTIVE:-0}" = "1" ]; then
    die "No usable public IP. Re-run with PUBIP=1.2.3.4 in the environment."
  fi
  printf "* Enter the server's public IP manually: "
  read -r PUBIP || true
  if valid_ip "$PUBIP"; then
    log "Using public IP: $PUBIP"
    break
  fi
  echo "  '$PUBIP' doesn't look like an IP. Try again."
  PUBIP=""
done
export PUBIP
ask PORT_START "First game port" "25590"
ask PORT_COUNT "How many game ports (25590, 25591, ...)" "10"

# Final cross-check: chosen panel ports must all differ, and game ports
# must not collide with them either.
check_distinct() { # check_distinct NAME1 VAL1 NAME2 VAL2
  if [ "$2" = "$4" ]; then
    die "$1 and $3 are both $2 - every service needs its own port."
  fi
}
check_distinct HTTP_PORT "$HTTP_PORT" HTTPS_PORT "$HTTPS_PORT"
check_distinct HTTP_PORT "$HTTP_PORT" WINGS_PORT "$WINGS_PORT"
check_distinct HTTP_PORT "$HTTP_PORT" SFTP_PORT "$SFTP_PORT"
check_distinct HTTPS_PORT "$HTTPS_PORT" WINGS_PORT "$WINGS_PORT"
check_distinct HTTPS_PORT "$HTTPS_PORT" SFTP_PORT "$SFTP_PORT"
check_distinct WINGS_PORT "$WINGS_PORT" SFTP_PORT "$SFTP_PORT"
if [ "$PORT_START" -lt 1024 ] || [ $((PORT_START + PORT_COUNT)) -gt 65536 ]; then
  die "Game port range $PORT_START-$((PORT_START + PORT_COUNT - 1)) is out of range."
fi
for svc_name in HTTP_PORT HTTPS_PORT WINGS_PORT SFTP_PORT; do
  eval "sp=\$$svc_name"
  if [ "$PORT_START" -le "$sp" ] && [ "$sp" -lt $((PORT_START + PORT_COUNT)) ]; then
    die "Game port range overlaps $svc_name ($sp). Move one of them."
  fi
done

export DOMAIN EMAIL ADMIN_USER ADMIN_PASS TIMEZONE
export HTTP_PORT HTTPS_PORT WINGS_PORT SFTP_PORT
export NODE_NAME NODE_MEM NODE_DISK NODE_CPU PORT_START PORT_COUNT PUBIP

# Persist answers for later modules + the final summary (safely quoted).
ENV_FILE="$TMPDIR_WORK/answers.env"
for v in DOMAIN EMAIL ADMIN_USER ADMIN_PASS TIMEZONE HTTP_PORT HTTPS_PORT WINGS_PORT SFTP_PORT NODE_NAME NODE_MEM NODE_DISK NODE_CPU PORT_START PORT_COUNT PUBIP; do
  declare -p "$v" >> "$ENV_FILE"
done
log "Answers saved."
