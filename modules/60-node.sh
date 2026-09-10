#!/bin/bash
# 60-node: create node + allocations in panel DB, write wings config, start wings.
set -euo pipefail
source "$(dirname "$0")/common.sh"

if [ "$HAVE_SSL" = "1" ]; then
  SCHEME="https"; SSL_ON="true"; REMOTE="https://$DOMAIN:$HTTPS_PORT"
else
  SCHEME="http"; SSL_ON="false"; REMOTE="http://$DOMAIN:$HTTP_PORT"
  warn "No SSL: wings will talk to the panel over plain HTTP."
fi

log "Creating node '$NODE_NAME'..."
cat > "$TMPDIR_WORK/makenode.php" <<'PHP_EOF'
use Illuminate\Support\Str;
use Illuminate\Container\Container;
use Illuminate\Contracts\Encryption\Encrypter;

$node = new \Everest\Models\Node();
$node->uuid = Str::uuid()->toString();
$node->public = true;
$node->name = '__NODE_NAME__';
$node->description = 'Primary node (__DOMAIN__)';
$node->fqdn = '__DOMAIN__';
$node->sftp_alias = null;
$node->listen_port_http = (int) '__WINGS_PORT__';
$node->listen_port_sftp = (int) '__SFTP_PORT__';
$node->public_port_http = (int) '__WINGS_PORT__';
$node->public_port_sftp = (int) '__SFTP_PORT__';
$node->scheme = '__SCHEME__';
$node->behind_proxy = false;
$node->maintenance_mode = false;
$node->memory = (int) '__NODE_MEM__';
$node->memory_overallocate = 0;
$node->disk = (int) '__NODE_DISK__';
$node->disk_overallocate = 0;
$node->upload_size = 100;
$node->daemon_token_id = Str::random(\Everest\Models\Node::DAEMON_TOKEN_ID_LENGTH);
$rawToken = Str::random(\Everest\Models\Node::DAEMON_TOKEN_LENGTH);
$node->daemon_token = Container::getInstance()->make(Encrypter::class)->encrypt($rawToken);
$node->daemon_base = '/var/lib/pterodactyl/volumes';
$node->deployable = false;
$node->deployable_free = false;
$node->deployment_fee = 0;
$node->save();
echo "NODE_ID=" . $node->id . "\n";
echo "NODE_UUID=" . $node->uuid . "\n";
echo "NODE_TOKEN_ID=" . $node->daemon_token_id . "\n";
echo "NODE_TOKEN=" . $rawToken . "\n";

$start = (int) '__PORT_START__';
$count = (int) '__PORT_COUNT__';
for ($p = $start; $p < $start + $count; $p++) {
    $a = new \Everest\Models\Allocation();
    $a->node_id = $node->id;
    $a->ip = '__PUBIP__';
    $a->ip_alias = '__DOMAIN__';
    $a->port = $p;
    $a->server_id = null;
    $a->notes = null;
    $a->save();
}
echo "ALLOCATIONS=" . $count . "\n";
PHP_EOF

sed -i -e "s/__NODE_NAME__/$NODE_NAME/" -e "s/__DOMAIN__/$DOMAIN/g" \
  -e "s/__WINGS_PORT__/$WINGS_PORT/" -e "s/__SFTP_PORT__/$SFTP_PORT/" \
  -e "s/__SCHEME__/$SCHEME/" -e "s/__NODE_MEM__/$NODE_MEM/" \
  -e "s/__NODE_DISK__/$NODE_DISK/" -e "s/__PORT_START__/$PORT_START/" \
  -e "s/__PORT_COUNT__/$PORT_COUNT/" -e "s/__PUBIP__/$PUBIP/" \
  "$TMPDIR_WORK/makenode.php"

cd "$PANEL_DIR"
echo "Running node-creation tinker..." | tee -a "$LOG"
TRIES=0
TINKER_RC=1
while [ "$TRIES" -lt 3 ]; do
  TRIES=$((TRIES + 1))
  if sudo -u www-data php artisan tinker --execute="$(cat "$TMPDIR_WORK/makenode.php")" > "$TMPDIR_WORK/node.out" 2>&1; then
    TINKER_RC=0
    break
  fi
  warn "node-creation tinker attempt $TRIES failed, retrying..."
  sleep 5
done
echo "tinker exit: $TINKER_RC (after $TRIES attempt(s))" | tee -a "$LOG"
echo "--- node creation output ---" | tee -a "$LOG"
tail -8 "$TMPDIR_WORK/node.out" | tee -a "$LOG"
grep -q "^NODE_UUID=" "$TMPDIR_WORK/node.out" || die "Node creation failed (see $TMPDIR_WORK/node.out)."

# shellcheck disable=SC1091
source <(grep -E "^(NODE_|ALLOCATIONS=)" "$TMPDIR_WORK/node.out")

log "Writing wings config..."
mkdir -p /etc/pterodactyl
CERT_BLOCK="enabled: false"
if [ "$HAVE_SSL" = "1" ]; then
  CERT_BLOCK="enabled: true
    cert: /etc/letsencrypt/live/$DOMAIN/fullchain.pem
    key: /etc/letsencrypt/live/$DOMAIN/privkey.pem"
fi
cat > /etc/pterodactyl/config.yml <<YAML
debug: false
uuid: $NODE_UUID
token_id: $NODE_TOKEN_ID
token: $NODE_TOKEN
api:
  host: 0.0.0.0
  port: $WINGS_PORT
  ssl:
    $CERT_BLOCK
  upload_limit: 100
system:
  data: /var/lib/pterodactyl/volumes
  sftp:
    bind_port: $SFTP_PORT
allowed_mounts: []
remote: '$REMOTE'
YAML
chmod 600 /etc/pterodactyl/config.yml

# Single-box fix: wings must reach the panel via loopback, not via the public
# IP (many VPS networks block hairpin NAT, causing timeouts). This only
# affects local resolution on this machine.
if ! grep -qE "[[:space:]]$DOMAIN([[:space:]]|$)" /etc/hosts; then
  log "Adding $DOMAIN to /etc/hosts for loopback (avoids hairpin NAT)..."
  echo "127.0.0.1 $DOMAIN" >> /etc/hosts
fi

log "Starting wings..."
systemctl start wings
log "Waiting for wings to become active (up to 90s)..."
READY=0
for i in $(seq 1 18); do
  if systemctl is-active wings >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 5
done
[ "$READY" = "1" ] || die "Wings failed to start (journalctl -u wings)."
log "Node ready: $NODE_NAME ($NODE_UUID), $ALLOCATIONS allocations."
