<?php

namespace Everest\Http\Controllers\Api\Client\Modpacks;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Cache;
use Everest\Http\Controllers\Api\Client\ClientApiController;

class FtbController extends ClientApiController
{
    public function index(): JsonResponse
    {
        $cacheFile = storage_path('app/ftb_cache/modpacks.json');

        if (!file_exists($cacheFile)) {
            return response()->json(['items' => [], 'total' => 0]);
        }

        $data = json_decode(file_get_contents($cacheFile), true);
        $items = $data['items'] ?? [];
        $sort = request('sort', 'installs');

        if ($sort === 'plays') {
            usort($items, fn($a, $b) => ($b['plays'] ?? 0) - ($a['plays'] ?? 0));
        } elseif ($sort === 'updated') {
            usort($items, fn($a, $b) => ($b['updated'] ?? 0) - ($a['updated'] ?? 0));
        }
        // Default: install count (already sorted in cache)

        return response()->json([
            'items' => $items,
            'total' => count($items),
        ]);
    }

    public function versions(int $id): JsonResponse
    {
        $cacheFile = storage_path('app/ftb_cache/modpacks.json');
        if (!file_exists($cacheFile)) {
            return response()->json(['items' => []]);
        }

        $data = json_decode(file_get_contents($cacheFile), true);
        $full = $data['full'] ?? [];
        $modpack = null;
        foreach ($full as $m) {
            if ($m['id'] === $id) {
                $modpack = $m;
                break;
            }
        }

        if (!$modpack) {
            return response()->json(['items' => []]);
        }

        $items = [];
        foreach ($modpack['versions'] ?? [] as $v) {
            $mcVer = '';
            $loader = '';
            foreach ($v['targets'] ?? [] as $t) {
                if ($t['name'] === 'minecraft') $mcVer = $t['version'];
                if (in_array($t['name'], ['forge', 'fabric', 'neoforge', 'quilt'])) $loader = $t['name'];
            }
            $items[] = [
                'id' => (string) $v['id'],
                'name' => $v['name'],
                'gameVersion' => $mcVer,
                'releaseType' => ($v['type'] ?? '') === 'release' ? 1 : 2,
                'loader' => $loader,
            ];
        }

        return response()->json(['items' => $items]);
    }
}
