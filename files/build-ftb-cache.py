#!/usr/bin/env python3
"""Build the FTB modpack cache used by the modpack browser.

Reads every public FTB modpack (id, name, versions, installs/plays) and writes
storage/app/ftb_cache/modpacks.json. Takes a few minutes (one request per pack).
Usage: build-ftb-cache.py /var/www/jexpanel
"""
import json
import sys
import time
import urllib.request

PANEL_DIR = sys.argv[1] if len(sys.argv) > 1 else "/var/www/jexpanel"
UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36"}


def get(url, timeout=20):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def main():
    all_data = get("https://api.feed-the-beast.com/v1/modpacks/public/modpack/all?offset=0&count=100")
    ids = all_data.get("packs", [])
    print(f"FTB: {len(ids)} modpacks to fetch...", flush=True)
    result = []
    for i, pid in enumerate(ids):
        try:
            d = get(f"https://api.feed-the-beast.com/v1/modpacks/public/modpack/{pid}")
        except Exception as e:  # noqa: BLE001 - keep going past single failures
            print(f"  [{i + 1}/{len(ids)}] skip {pid}: {e}", flush=True)
            continue
        if d.get("status") != "success":
            continue
        versions = d.get("versions", [])
        result.append(
            {
                "id": d["id"],
                "name": d["name"],
                "slug": d["slug"],
                "description": (d.get("description") or "")[:300],
                "installs": d.get("installs", 0),
                "plays": d.get("plays", 0),
                "updated": max((v.get("updated", 0) for v in versions), default=0),
                "versions": versions,
            }
        )
        print(f"  [{i + 1}/{len(ids)}] {d['name']}", flush=True)
        time.sleep(0.2)

    result.sort(key=lambda x: -x.get("installs", 0))
    slim = [
        {
            "id": r["id"],
            "name": r["name"],
            "slug": r["slug"],
            "summary": r["description"][:150],
            "installs": r["installs"],
            "plays": r["plays"],
            "updated": r["updated"],
            "logo": f"https://api.feed-the-beast.com/v1/modpacks/public/modpack/{r['id']}/art",
        }
        for r in result
    ]
    out = {"items": slim, "full": result, "total": len(result)}
    with open(f"{PANEL_DIR}/storage/app/ftb_cache/modpacks.json", "w") as f:
        json.dump(out, f)
    print(f"Wrote {len(result)} FTB modpacks")


if __name__ == "__main__":
    main()
