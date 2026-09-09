#!/bin/bash
# 40-nginx: vhosts (port 80 ACME + redirect, custom HTTP redirect, panel HTTPS) + Let's Encrypt.
set -euo pipefail
source "$(dirname "$0")/common.sh"

HAVE_SSL=0

if [ "$HTTPS_PORT" = "443" ]; then
  HTTPS_URL="https://$DOMAIN"
else
  HTTPS_URL="https://$DOMAIN:$HTTPS_PORT"
fi

mkdir -p /var/www/html
chown www-data:www-data /var/www/html

# The custom HTTP port gets its server block only AFTER we know whether
# SSL exists: redirect-to-HTTPS with SSL, panel-itself without.
if [ "$HTTP_PORT" != "80" ] && port_in_use "$HTTP_PORT"; then
  die "Port $HTTP_PORT is already in use on this machine. Pick a free one."
fi

if port_in_use 80; then
  warn "Port 80 is already in use. Let's Encrypt http-01 checks need port 80 free - SSL issuance will likely fail (panel will still work over plain HTTP)."
fi

log "Writing nginx vhost (port 80 ACME + redirect)..."
fetch "files/nginx-http.conf" "$TMPDIR_WORK/nginx-http.conf"
sed -e "s|{{DOMAIN}}|$DOMAIN|g" -e "s|{{HTTPS_URL}}|$HTTPS_URL|g" \
  "$TMPDIR_WORK/nginx-http.conf" > /etc/nginx/sites-available/panel.conf

# Avoid clashing with Ubuntu's default site on port 80.
if [ -e /etc/nginx/sites-enabled/default ]; then
  mv /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.disabled-by-panel-installer
  log "Disabled default nginx site."
fi
ln -sf /etc/nginx/sites-available/panel.conf /etc/nginx/sites-enabled/panel.conf
chown -R www-data:www-data "$PANEL_DIR"
nginx -t
systemctl reload-or-restart nginx

log "Requesting Let's Encrypt certificate for $DOMAIN..."
if certbot certonly --webroot -w /var/www/html -d "$DOMAIN" \
    --email "$EMAIL" --agree-tos --non-interactive >>"$LOG" 2>&1; then
  HAVE_SSL=1
  log "Certificate obtained."
else
  warn "Let's Encrypt failed (DNS must point at this server and port 80 must be reachable). Continuing WITHOUT SSL - finish DNS/port 80, then run certbot manually."
fi

if [ "$HAVE_SSL" = "1" ]; then
  if port_in_use "$HTTPS_PORT"; then
    die "Port $HTTPS_PORT became used meanwhile. Free it and re-run."
  fi
  if [ "$HTTP_PORT" != "80" ]; then
    log "Adding HTTP redirect on $HTTP_PORT..."
    cat >> /etc/nginx/sites-available/panel.conf <<REDIRECT

server {
    listen $HTTP_PORT;
    listen [::]:$HTTP_PORT;
    server_name $DOMAIN;
    return 301 ${HTTPS_URL}\$request_uri;
}
REDIRECT
  fi
  log "Enabling HTTPS on $HTTPS_PORT..."
  fetch "files/nginx-ssl.conf" "$TMPDIR_WORK/nginx-ssl.conf"
  sed -e "s|{{DOMAIN}}|$DOMAIN|g" -e "s|{{HTTPS_PORT}}|$HTTPS_PORT|g" -e "s|{{PANEL_DIR}}|$PANEL_DIR|g" \
    "$TMPDIR_WORK/nginx-ssl.conf" > /etc/nginx/sites-available/panel-ssl.conf
  ln -sf /etc/nginx/sites-available/panel-ssl.conf /etc/nginx/sites-enabled/panel-ssl.conf
  nginx -t
  systemctl reload-or-restart nginx
else
  # No certificate: the HTTP port must SERVE the panel (redirecting would
  # loop to an https:// URL with no listener and break wings + logins).
  log "No SSL - serving panel over plain HTTP on $HTTP_PORT..."
  fetch "files/nginx-plain.conf" "$TMPDIR_WORK/nginx-plain.conf"
  sed -e "s|{{DOMAIN}}|$DOMAIN|g" -e "s|{{HTTP_PORT}}|$HTTP_PORT|g" -e "s|{{PANEL_DIR}}|$PANEL_DIR|g" \
    "$TMPDIR_WORK/nginx-plain.conf" > /etc/nginx/sites-available/panel-plain.conf
  ln -sf /etc/nginx/sites-available/panel-plain.conf /etc/nginx/sites-enabled/panel-plain.conf
  nginx -t
  systemctl reload-or-restart nginx
fi

# Persist for the summary.
{ declare -p HAVE_SSL HTTPS_URL; } >> "$TMPDIR_WORK/answers.env"
log "Nginx done (SSL: $HAVE_SSL)."
