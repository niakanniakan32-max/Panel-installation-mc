<?php

namespace Everest\Http\Controllers\Api\Client\Modpacks;

use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Http;
use Everest\Http\Controllers\Api\Client\ClientApiController;

class CurseforgeController extends ClientApiController
{
    private const API = 'https://api.curse.tools/v1';

    private static function detectLoader(array $gameVersions): string
    {
        foreach ($gameVersions as $gv) {
            $low = strtolower((string) $gv);
            if (in_array($low, ['forge', 'fabric', 'quilt', 'neoforge'], true)) {
                return $low;
            }
        }
        return 'forge';
    }

    private static function detectMcVersion(array $gameVersions): string
    {
        foreach ($gameVersions as $gv) {
            if (preg_match('/^\d+\.\d+/', (string) $gv)) {
                return (string) $gv;
            }
        }
        return $gameVersions[0] ?? 'unknown';
    }

    public function search(Request $request): JsonResponse
    {
        $search = $request->input('q', '');
        $sortField = (int) $request->input('sortField', 2); // 2 = TotalDownloads
        $pageSize = 20;
        $index = (int) $request->input('page', 0);
        $sortOrder = $request->input('sortOrder', 'desc');

        $params = [
            'gameId' => 432,
            'classId' => 4471, // Modpacks
            'pageSize' => $pageSize,
            'index' => $index,
            'sortField' => $sortField,
            'sortOrder' => $sortOrder,
        ];

        if ($search) {
            $params['searchFilter'] = $search;
        }

        $resp = Http::get(self::API . '/mods/search', $params);

        if ($resp->failed()) {
            return response()->json(['error' => 'CurseForge mirror failed', 'status' => $resp->status()], 502);
        }

        $data = $resp->json();
        $items = [];

        foreach ($data['data'] ?? [] as $m) {
            $items[] = [
                'id' => $m['id'],
                'name' => $m['name'],
                'slug' => $m['slug'] ?? '',
                'summary' => $m['summary'] ?? '',
                'downloads' => $m['downloadCount'] ?? 0,
                'logo' => $m['logo']['thumbnailUrl'] ?? null,
                'authors' => array_map(fn($a) => $a['name'] ?? 'unknown', $m['authors'] ?? []),
            ];
        }

        return response()->json([
            'items' => $items,
            'total' => $data['pagination']['totalCount'] ?? 0,
            'page' => $index,
        ]);
    }

    public function versions(int $modId): JsonResponse
    {
        $resp = Http::get(self::API . "/mods/{$modId}/files", ['pageSize' => 30]);

        if ($resp->failed()) {
            return response()->json(['error' => 'CF mirror failed'], 502);
        }

        $data = $resp->json();
        $items = [];
        $seen = [];
        $serverPackIds = [];

        foreach ($data['data'] ?? [] as $f) {
            $seen[$f['id']] = true;
            if (!empty($f['serverPackFileId']) && empty($seen[$f['serverPackFileId']])) {
                $serverPackIds[$f['serverPackFileId']] = true;
            }
            $items[] = [
                'id' => $f['id'],
                'name' => $f['displayName'],
                'gameVersion' => self::detectMcVersion($f['gameVersions'] ?? []),
                'releaseType' => match ($f['releaseType'] ?? 1) {
                    1 => 1, // Release
                    2 => 2, // Beta
                    3 => 3, // Alpha
                    default => 1,
                },
                'loader' => self::detectLoader($f['gameVersions'] ?? []),
                'isServerPack' => $f['isServerPack'] ?? false,
                'serverPackFileId' => $f['serverPackFileId'] ?? null,
                'fileLength' => $f['fileLength'] ?? null,
                'downloadUrl' => $f['downloadUrl'] ?? null,
            ];
        }

        // Server packs are hidden from the list endpoint — resolve them via
        // the serverPackFileId link so they can be recommended.
        $missing = array_values(array_diff(array_keys($serverPackIds), array_keys($seen)));
        if (!empty($missing)) {
            $fetchPack = function ($fid) use ($modId) {
                for ($try = 0; $try < 3; $try++) {
                    try {
                        $r = Http::timeout(15)->get(self::API . "/mods/{$modId}/files/{$fid}");
                        if ($r->successful() && !empty($r->json()['data'])) {
                            return $r->json()['data'];
                        }
                    } catch (\Throwable $e) {
                        // retry below
                    }
                    sleep(1);
                }
                return null;
            };
            $responses = Http::pool(function ($pool) use ($modId, $missing, $fetchPack) {
                // Prime the pool for speed; failures are retried sequentially below.
                $reqs = [];
                foreach ($missing as $fid) {
                    $reqs[] = $pool->get(self::API . "/mods/{$modId}/files/{$fid}");
                }
                return $reqs;
            });
            $serverPacks = [];
            $failedIds = [];
            foreach ($responses as $i => $r) {
                $fid = $missing[$i] ?? null;
                try {
                    $f = ($r && $r->successful()) ? ($r->json()['data'] ?? null) : null;
                } catch (\Throwable $e) {
                    $f = null;
                }
                if (!$f && $fid !== null) {
                    $failedIds[] = $fid;
                    continue;
                }
                if (!$f) continue;
                $serverPacks[] = [
                    'id' => $f['id'],
                    'name' => $f['displayName'],
                    'gameVersion' => self::detectMcVersion($f['gameVersions'] ?? []),
                    'releaseType' => match ($f['releaseType'] ?? 1) {
                        1 => 1,
                        2 => 2,
                        3 => 3,
                        default => 1,
                    },
                    'loader' => self::detectLoader($f['gameVersions'] ?? []),
                    'isServerPack' => true,
                    'serverPackFileId' => null,
                    'fileLength' => $f['fileLength'] ?? null,
                    'downloadUrl' => $f['downloadUrl'] ?? null,
                ];
            }
            // Sequential retry for anything the pool dropped.
            foreach ($failedIds as $fid) {
                $f = $fetchPack($fid);
                if (!$f) continue;
                $serverPacks[] = [
                    'id' => $f['id'],
                    'name' => $f['displayName'],
                    'gameVersion' => self::detectMcVersion($f['gameVersions'] ?? []),
                    'releaseType' => match ($f['releaseType'] ?? 1) {
                        1 => 1,
                        2 => 2,
                        3 => 3,
                        default => 1,
                    },
                    'loader' => self::detectLoader($f['gameVersions'] ?? []),
                    'isServerPack' => true,
                    'serverPackFileId' => null,
                    'fileLength' => $f['fileLength'] ?? null,
                    'downloadUrl' => $f['downloadUrl'] ?? null,
                ];
            }
            // Server packs first (recommended), newest first.
            usort($serverPacks, fn($a, $b) => $b['id'] <=> $a['id']);
            $items = array_merge($serverPacks, $items);
        }

        return response()->json(['items' => $items]);
    }

    public function downloadUrl(int $modId, int $fileId): JsonResponse
    {
        $resp = Http::get(self::API . "/mods/{$modId}/files", ['pageSize' => 100]);
        if ($resp->successful()) {
            foreach ($resp->json()['data'] ?? [] as $f) {
                if ($f['id'] === $fileId) {
                    return response()->json([
                        'url' => $f['downloadUrl'],
                        'filename' => $f['displayName'] ?? 'modpack.zip',
                    ]);
                }
            }
        }

        // Server packs are hidden from the list — try a direct lookup.
        $single = Http::get(self::API . "/mods/{$modId}/files/{$fileId}");
        if ($single->successful() && !empty($single->json()['data']['downloadUrl'])) {
            $f = $single->json()['data'];
            return response()->json([
                'url' => $f['downloadUrl'],
                'filename' => $f['displayName'] ?? 'modpack.zip',
            ]);
        }

        return response()->json(['error' => 'File not found'], 404);
    }
}
