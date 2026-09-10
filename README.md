# Panel one-link installer

Installs **Jexpanel/Everest + Wings + modpack browser** (Modrinth, CurseForge, FTB)
on a fresh Ubuntu VPS with one command — the same stack as `mc.nnetwork998.ir`.

## One-link install

```bash
bash <(curl -sL https://raw.githubusercontent.com/niakanniakan32-max/Panel-installation-mc/main/install.sh)
```

> Replace `niakanniakan32-max/Panel-installation-mc` with your repo path after uploading these files,
> keeping the same layout (`install.sh`, `lib/`, `modules/`, `files/`).
> Also replace the `REPO_RAW` default inside `install.sh`, or export it:
> `REPO_RAW=https://raw.githubusercontent.com/niakanniakan32-max/Panel-installation-mc/main bash <(...)`.

## Requirements (new VPS)

- Ubuntu **22.04 or 24.04** x86_64, root access, fresh machine
- A domain whose **A-record points at the server** (needed for SSL)
- Ports: installer asks with recommendations —
  **8443/8081/8444 recommended** if x-ui or similar tools are present
  (x-ui uses 443 + 8080, so 443/8080 are warned against).
- 4 GB+ RAM if you plan to run big modpacks (RLCraft etc.)

## Unattended install

```bash
curl -sL https://raw.githubusercontent.com/niakanniakan32-max/Panel-installation-mc/main/install.sh -o install.sh
DOMAIN=panel.example.com EMAIL=admin@example.com \
ADMIN_USER=admin ADMIN_PASS='pick-something-strong' \
bash install.sh --non-interactive
```

All supported env vars: `DOMAIN EMAIL ADMIN_USER ADMIN_PASS TIMEZONE
HTTP_PORT HTTPS_PORT WINGS_PORT SFTP_PORT NODE_NAME NODE_MEM NODE_DISK
NODE_CPU PORT_START PORT_COUNT JEXPANEL_VERSION REPO_RAW NPM_REGISTRY`.
If the official npm registry is slow from your country, pre-set e.g.
`NPM_REGISTRY=https://registry.npmmirror.com` (the installer also retries
with this mirror automatically if the first attempt yields nothing).
`--dry-run` prints the plan without changing anything.

## What it installs

1. Deps: PHP 8.5, composer, MariaDB, nginx, Redis, Docker, Node 22, certbot
2. Jexpanel (`JEXPANEL_VERSION`, default `v4.0.7`) + DB + admin + setup wizard skipped
3. nginx (port-80 ACME + redirect, panel HTTPS) + Let's Encrypt via webroot
4. Wings binary + systemd + node + allocations + `config.yml`, wings started
5. Modrinth Generic egg: POSIX installer, CurseForge/FTB/manual support, Java 17 installer image
6. Modpack browser: CurseForge + FTB + upload endpoints, `/browse` page, in-form popup, FTB cache, frontend build
7. Verification + credentials in `/root/panel-credentials.env` (chmod 600)

## Notes

- Custom panel files in this repo were extracted from a working Jexpanel
  `v4.0.7` install. If you bump `JEXPANEL_VERSION`, re-extract
  `NewServerContainer.tsx` / `ModpackPicker.tsx` and re-apply the popup wiring.
- The egg install script must stay **POSIX sh** (installer entrypoint is
  `/bin/ash`): no `[[ ]]`, no `=~`, no `${var:0:4}`. Validate with:
  `docker run --rm -v file:/t.sh ghcr.io/pterodactyl/installers:alpine /bin/ash -n /t.sh`
- CurseForge search runs through the public `api.curse.tools` mirror (no key needed).
- FTB list is pre-fetched at install time (~94 requests, a few minutes).
