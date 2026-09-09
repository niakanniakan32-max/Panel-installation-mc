#!/bin/bash
# 80-modpacks: endpoints, /browse page, popup picker, FTB cache, frontend build.
set -euo pipefail
source "$(dirname "$0")/common.sh"

log "Copying modpack controllers + views + picker..."
fetch "files/app/Http/Controllers/Api/Client/Modpacks/CurseforgeController.php" \
  "$PANEL_DIR/app/Http/Controllers/Api/Client/Modpacks/CurseforgeController.php"
fetch "files/app/Http/Controllers/Api/Client/Modpacks/FtbController.php" \
  "$PANEL_DIR/app/Http/Controllers/Api/Client/Modpacks/FtbController.php"
fetch "files/app/Http/Controllers/Api/Client/Modpacks/UploadController.php" \
  "$PANEL_DIR/app/Http/Controllers/Api/Client/Modpacks/UploadController.php"
mkdir -p "$PANEL_DIR/resources/views/browse"
fetch "files/resources/views/browse/index.blade.php" \
  "$PANEL_DIR/resources/views/browse/index.blade.php"
fetch "files/resources/scripts/components/admin/management/servers/modpack/ModpackPicker.tsx" \
  "$PANEL_DIR/resources/scripts/components/admin/management/servers/modpack/ModpackPicker.tsx"
fetch "files/resources/scripts/components/admin/management/servers/NewServerContainer.tsx" \
  "$PANEL_DIR/resources/scripts/components/admin/management/servers/NewServerContainer.tsx"
chown -R www-data:www-data \
  "$PANEL_DIR/app/Http/Controllers/Api/Client/Modpacks" \
  "$PANEL_DIR/resources/views/browse" \
  "$PANEL_DIR/resources/scripts/components/admin/management/servers"

log "Registering modpack routes..."
python3 - "$PANEL_DIR" <<'PYEOF'
import re
import sys

panel = sys.argv[1]

# 1) Client API routes (browsing needs a logged-in session; same as upstream file).
p = f"{panel}/routes/api-client.php"
src = open(p).read()
block = """    // Modpack providers (no server context needed for browsing)
    Route::group(['prefix' => '/modpacks'], function () {
        Route::get('/curseforge/search', [Client\\Modpacks\\CurseforgeController::class, 'search']);
        Route::get('/curseforge/versions/{modId}', [Client\\Modpacks\\CurseforgeController::class, 'versions']);
        Route::get('/curseforge/download/{modId}/{fileId}', [Client\\Modpacks\\CurseforgeController::class, 'downloadUrl']);
        Route::get('/ftb-list', [Client\\Modpacks\\FtbController::class, 'index']);
        Route::get('/ftb-versions/{id}', [Client\\Modpacks\\FtbController::class, 'versions']);
        Route::post('/upload', [Client\\Modpacks\\UploadController::class, 'upload']);
    });

"""
if "'/curseforge/search'" not in src and 'modpacks/curseforge' not in src:
    marker = "    Route::prefix('/billing')"
    assert marker in src, "billing route marker not found"
    src = src.replace(marker, block + marker, 1)
    open(p, "w").write(src)
    print("api-client.php patched")
else:
    print("api-client.php already patched")

# 2) Standalone /browse page - must come BEFORE the /{react} SPA fallback.
p = f"{panel}/routes/base.php"
src = open(p).read()
route = "Route::get('/browse', function() { return view('browse.index'); })->name('browse.index');\n"
if "/browse" not in src:
    fallback = "Route::get('/{react}'"
    assert fallback in src, "SPA fallback not found"
    src = src.replace(fallback, route + fallback, 1)
    open(p, "w").write(src)
    print("base.php patched")
else:
    print("base.php already patched")
PYEOF

log "Building FTB cache (a few minutes, 90+ small requests)..."
mkdir -p "$PANEL_DIR/storage/app/ftb_cache"
chown www-data:www-data "$PANEL_DIR/storage/app/ftb_cache"
fetch "files/build-ftb-cache.py" "$TMPDIR_WORK/build-ftb-cache.py"
sudo -u www-data python3 "$TMPDIR_WORK/build-ftb-cache.py" "$PANEL_DIR" 2>&1 | tail -2 | tee -a "$LOG"

log "Building panel frontend (npm install + build, several minutes)..."
cd "$PANEL_DIR"
sudo -u www-data npm install --no-audit --no-fund 2>&1 | tail -2 | tee -a "$LOG"
sudo -u www-data npm run build 2>&1 | tail -3 | tee -a "$LOG"
chown -R www-data:www-data "$PANEL_DIR/public/build" "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"

cd "$PANEL_DIR"
sudo -u www-data php artisan optimize:clear -q
log "Modpack browser ready: /browse page + in-form popup."
