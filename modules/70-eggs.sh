#!/bin/bash
# 70-eggs: import Modrinth Generic egg (pelican base + our POSIX installer + extra vars).
set -euo pipefail
source "$(dirname "$0")/common.sh"

NEST_ID="$(cd "$PANEL_DIR" && sudo -u www-data php artisan tinker --execute='echo \Everest\Models\Nest::where("name","Minecraft")->value("id") ?? \Everest\Models\Nest::first()->id;' 2>/dev/null | tail -1 | tr -d '\r')"
log "Minecraft nest id: $NEST_ID"

log "Fetching pelican Modrinth egg definition..."
curl -fsSL -o "$TMPDIR_WORK/modrinth.json" \
  "https://raw.githubusercontent.com/pelican-eggs/minecraft/main/java/modrinth/egg-pterodactyl-modrinth-generic.json"
fetch "files/egg-modrinth-install.sh" "$TMPDIR_WORK/egg-modrinth-install.sh"

cat > "$TMPDIR_WORK/makeegg.php" <<'PHP_EOF'
use Illuminate\Support\Str;

$payload = json_decode(file_get_contents('__WORKDIR__/modrinth.json'), true);
unset($payload['_comment'], $payload['meta'], $payload['exported_at']);
$config = $payload['config'] ?? [];

$egg = new \Everest\Models\Egg();
$egg->nest_id = (int) '__NEST_ID__';
$egg->uuid = Str::uuid()->toString();
$egg->name = $payload['name'];
$egg->author = $payload['author'] ?? 'pelican-eggs@example.com';
$egg->description = $payload['description'];
$egg->features = $payload['features'] ?? [];
$egg->docker_images = $payload['docker_images'] ?? [];
$egg->file_denylist = $payload['file_denylist'] ?? [];
$egg->startup = $payload['startup'];
$egg->config_files = $config['files'] ?? '{}';
$egg->config_startup = $config['startup'] ?? '{"done": "Done"}';
$egg->config_stop = $config['stop'] ?? 'stop';
$egg->script_install = file_get_contents('__WORKDIR__/egg-modrinth-install.sh');
// Pinned installer image: must contain Java (plain alpine does not).
$egg->script_container = 'ghcr.io/pelican-eggs/installers:java_17';
$egg->script_entry = 'bash';
$egg->force_outgoing_ip = false;
$egg->save();
echo "EGG_ID=" . $egg->id . "\n";

// Base variables from the egg definition.
foreach ($payload['variables'] ?? [] as $v) {
    $var = new \Everest\Models\EggVariable();
    $var->egg_id = $egg->id;
    $var->name = $v['name'];
    $var->description = $v['description'] ?? '';
    $var->env_variable = $v['env_variable'];
    $var->default_value = $v['default_value'] ?? '';
    $var->user_viewable = $v['user_viewable'] ?? true;
    $var->user_editable = $v['user_editable'] ?? true;
    $var->rules = $v['rules'] ?? 'string';
    $var->field_type = $v['field_type'] ?? 'text';
    $var->save();
}

// Extra variables our installer + browser need.
$extra = [
    ['Provider', 'PROVIDER', 'modrinth, curseforge, ftb or manual (auto-filled by modpack browser)', 'modrinth'],
    ['Modpack ZIP Path', 'MODPACK_ZIP', 'Server path of an uploaded modpack .zip (manual installs)', ''],
    ['MC Version', 'MC_VERSION', 'Minecraft version (auto-filled by modpack browser)', ''],
    ['Mod Loader', 'LOADER', 'forge, fabric, neoforge or quilt (auto-filled by modpack browser)', ''],
];
foreach ($extra as [$n, $e, $d, $dv]) {
    $var = new \Everest\Models\EggVariable();
    $var->egg_id = $egg->id;
    $var->name = $n;
    $var->description = $d;
    $var->env_variable = $e;
    $var->default_value = $dv;
    $var->user_viewable = true;
    $var->user_editable = ($e !== 'PROVIDER');
    $var->rules = 'nullable|string|max:2000';
    $var->field_type = 'text';
    $var->save();
}
// CurseForge passes full download URLs here - needs room beyond the stock limit.
$pid = $egg->variables()->where('env_variable', 'PROJECT_ID')->first();
if ($pid) {
    $pid->rules = 'nullable|string|max:2000';
    $pid->save();
}
echo "EGG_VARS_DONE=1\n";
PHP_EOF

sed -i -e "s|__WORKDIR__|$TMPDIR_WORK|g" -e "s|__NEST_ID__|$NEST_ID|" "$TMPDIR_WORK/makeegg.php"

cd "$PANEL_DIR"
sudo -u www-data php artisan tinker --execute="$(cat "$TMPDIR_WORK/makeegg.php")" > "$TMPDIR_WORK/egg.out" 2>&1
tail -3 "$TMPDIR_WORK/egg.out" | tee -a "$LOG"
grep -q "^EGG_VARS_DONE=1" "$TMPDIR_WORK/egg.out" || die "Egg import failed."
log "Modrinth Generic egg imported."
