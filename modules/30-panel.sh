#!/bin/bash
# 30-panel: download Jexpanel, DB, env, key, migrate+seed, admin, setup flag.
set -euo pipefail
source "$(dirname "$0")/common.sh"

DB_NAME="jexpanel"
DB_USER="jexpanel"
DB_PASS="$(gen_pass 24)"

log "Downloading Jexpanel $JEXPANEL_VERSION..."
mkdir -p "$PANEL_DIR"
curl -fsSL -o "$TMPDIR_WORK/panel.tar.gz" \
  "https://github.com/Jexactyl/Jexactyl/releases/download/$JEXPANEL_VERSION/panel.tar.gz"
tar -xzf "$TMPDIR_WORK/panel.tar.gz" -C "$PANEL_DIR"
chown -R www-data:www-data "$PANEL_DIR"

log "Creating database..."
mariadb -uroot <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

log "Writing .env..."
cat > "$PANEL_DIR/.env" <<ENV
APP_ENV=production
APP_DEBUG=false
APP_KEY=
APP_TIMEZONE=$TIMEZONE
APP_URL=https://$DOMAIN:$HTTPS_PORT
APP_LOCALE=en
APP_ENVIRONMENT_ONLY=false
LOG_CHANNEL=daily
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=$DB_NAME
DB_USERNAME=$DB_USER
DB_PASSWORD=$DB_PASS
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379
CACHE_DRIVER=file
SESSION_DRIVER=file
QUEUE_CONNECTION=sync
MAIL_MAILER=log
MAIL_HOST=localhost
MAIL_PORT=2525
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS=null
MAIL_FROM_NAME=\${APP_NAME}
ENV
# NOTE: the heredoc above is UNQUOTED so $VARS expand; ${APP_NAME} intentionally
# stays literal for Laravel (APP_NAME is not defined at install time).
chown www-data:www-data "$PANEL_DIR/.env"
chmod 640 "$PANEL_DIR/.env"

cd "$PANEL_DIR"
log "Installing composer deps (takes a few minutes)..."
COMPOSER_ALLOW_SUPERUSER=1 sudo -u www-data composer install --no-dev --optimize-autoloader -q

log "App key + storage link + migrate..."
sudo -u www-data php artisan key:generate --force -q
sudo -u www-data php artisan storage:link -q
sudo -u www-data php artisan migrate --force --seed

log "Creating admin user..."
sudo -u www-data php artisan p:user:make \
  --email="$EMAIL" --username="$ADMIN_USER" \
  --name-first="Admin" --name-last="User" \
  --password="$ADMIN_PASS" --admin=1

log "Skipping first-run wizard..."
sudo -u www-data php artisan tinker --execute='Everest\Models\Setting::set("settings::app:setup", "true"); echo "setup flag set\n";'

# Save DB creds for the final summary (root-only file at the end).
{
  declare -p DB_NAME DB_USER DB_PASS
} >> "$TMPDIR_WORK/answers.env"

log "Panel installed."
