<?php

namespace Everest\Http\Controllers\Api\Client\Modpacks;

use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Storage;
use Everest\Http\Controllers\Api\Client\ClientApiController;

class UploadController extends ClientApiController
{
    public function upload(Request $request): JsonResponse
    {
        $request->validate([
            'modpack' => 'required|file|max:1024|mimes:zip',
        ]);

        $file = $request->file('modpack');
        $name = preg_replace('/[^a-zA-Z0-9._-]/', '_', $file->getClientOriginalName());
        $path = '/tmp/modpack-uploads/' . uniqid('mp_', true) . '_' . $name;

        // Ensure directory exists
        if (!is_dir('/tmp/modpack-uploads')) {
            mkdir('/tmp/modpack-uploads', 0755, true);
        }

        $file->move('/tmp/modpack-uploads', basename($path));

        return response()->json([
            'path' => $path,
            'size' => filesize($path),
            'name' => $name,
        ]);
    }
}
