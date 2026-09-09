#!/bin/bash
# 20-deps: apt packages, PHP 8.5, composer, MariaDB, nginx, Redis, Docker, Node 22, certbot.
set -euo pipefail
source "$(dirname "$0")/common.sh"

export DEBIAN_FRONTEND=noninteractive

log "Updating apt..."
apt-get update -y

log "Installing base packages..."
apt-get install -y ca-certificates curl wget git unzip tar cron gnupg lsb-release \
  software-properties-common apt-transport-https dnsutils python3

# PHP 8.5 (Jexpanel needs ^8.4 || ^8.5)
if ! command -v php >/dev/null || ! php -v | head -1 | grep -q "8\.[45]"; then
  log "Adding PHP repo (ondrej)..."
  add-apt-repository -y ppa:ondrej/php
  apt-get update -y
fi
log "Installing PHP 8.5 + extensions..."
apt-get install -y php8.5 php8.5-cli php8.5-common php8.5-fpm php8.5-mysql php8.5-mbstring \
  php8.5-bcmath php8.5-xml php8.5-curl php8.5-zip php8.5-gd php8.5-redis

log "Installing MariaDB, nginx, Redis..."
apt-get install -y mariadb-server nginx redis-server
systemctl enable --now mariadb redis-server
systemctl enable nginx

# Composer
if ! command -v composer >/dev/null; then
  log "Installing composer..."
  curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
  php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
  rm -f /tmp/composer-setup.php
fi

# Docker (official repo)
if ! command -v docker >/dev/null; then
  log "Installing Docker..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io
  systemctl enable --now docker
else
  log "Docker already present."
  systemctl enable --now docker || true
fi

# Node.js 22 (frontend build)
if ! command -v node >/dev/null || [ "$(node -v | cut -d. -f1 | tr -d v)" -lt 22 ]; then
  log "Installing Node.js 22..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
  apt-get update -y
  apt-get install -y nodejs
fi
log "node $(node -v), php $(php -v | head -1)"

# Certbot (webroot mode, no nginx plugin needed)
apt-get install -y certbot

log "Dependencies done."
