# CLAUDE.md — bifrost

## Project Overview
Multi-game dedicated server manager on GCP Compute Engine using Docker. Supports Valheim, Minecraft, 7 Days to Die, and Enshrouded. Designed for cheap pay-per-use hosting with easy stop/start for casual play sessions.

## Tech Stack
- **GCP Compute Engine**: e2-small/e2-medium VMs with Container-Optimized OS (COS)
- **Docker**: Game-specific server images (one container per VM)
- **gcloud CLI**: All infrastructure management
- **Bash scripts**: Core engine for setup/start/stop/backup/teardown
- **Flask**: Optional local web UI at localhost:5000

## Supported Games

| Game | Docker Image | Ports | Default VM | Ready Signal |
|------|-------------|-------|-----------|--------------|
| Valheim | `lloesche/valheim-server` | UDP 2456-2458 | e2-small | `Registering lobby` |
| Minecraft | `itzg/minecraft-server` | TCP 25565 | e2-small | `Done (` |
| 7 Days to Die | `vinanrra/7dtd-server` | UDP 26900-26902, TCP 26900 | e2-medium | `GameServer.Init successful` |
| Enshrouded | `mornedhels/enshrouded-server` | UDP 15636-15637 | e2-medium | `HostOnline` |

**7DTD and Enshrouded require e2-medium (4GB RAM).** Setup will auto-upgrade from e2-small with a warning. Set `FORCE_SMALL=1` to override.

## Key Decisions
- **GCP over Fly.io**: Cheaper (~$0.84/mo vs ~$4/mo) because stopped VMs only bill for disk, and ephemeral IPs are nearly free
- **GCP over Railway**: Railway has no inbound UDP support (Valheim requires UDP 2456-2457)
- **Ephemeral IP by default**: Saves ~$3.50/mo vs static IP. IP changes on restart but start script prints it
- **Container-Optimized OS**: Preinstalled Docker, minimal attack surface, auto-updates
- **One VM per game**: Each game gets its own VM, disk, and firewall rule with game-prefixed names
- **Bash scripts as core engine**: Web UI is a thin Flask wrapper that calls `./bifrost` commands via subprocess

## Architecture: Multi-Game Config

Game-specific config lives in `scripts/games/<game>.sh`. Each file defines a standard set of variables:
- `GAME_ID`, `GAME_DISPLAY_NAME` — identity
- `VM_NAME`, `DISK_NAME`, `FIREWALL_RULE`, `NETWORK_TAG` — GCP resources
- `GAME_IMAGE`, `GAME_CONTAINER_NAME`, `GAME_PORTS_*` — Docker config
- `GAME_DEFAULT_SIZE`, `GAME_MIN_SIZE` — VM sizing
- `GAME_READY_SIGNAL`, `GAME_READY_TIMEOUT` — health check
- `GAME_DATA_MOUNT`, `GAME_DATA_VOLUME`, `GAME_WORLD_SUBDIR` — data paths
- `game_docker_env_flags()` — function emitting `-e KEY=VAL` flags for docker run
- `game_validate_config()` — function for game-specific validation (password checks, min size)

`scripts/config.sh` loads the game config based on the `GAME` env var (default: `valheim`), and provides `generate_startup_script()` used by both setup.sh and restore.sh.

## GCP Resources Per Game
Each game creates its own set of resources:
- **Valheim**: `valserver`, `valserver-data`, `valserver-allow-valheim` (kept from pre-rename to preserve existing resources)
- **Minecraft**: `bifrost-minecraft`, `bifrost-minecraft-data`, `bifrost-allow-minecraft`
- **7DTD**: `bifrost-7dtd`, `bifrost-7dtd-data`, `bifrost-allow-7dtd`
- **Enshrouded**: `bifrost-enshrouded`, `bifrost-enshrouded-data`, `bifrost-allow-enshrouded`

## File Layout
```
bifrost                          — CLI entry point (./bifrost --game=minecraft start, etc.)
.env                             — GCP_PROJECT + FTP credentials (gitignored, auto-sourced by ./bifrost)
docker-compose.yml               — Local testing (profiles: valheim, minecraft, 7dtd, enshrouded)
scripts/
  config.sh                      — Shared config, game loader, generate_startup_script()
  setup.sh                       — One-time GCP resource creation (VM, disk, firewall)
  start.sh                       — Start VM, wait for healthy, print IP
  stop.sh                        — Graceful save → wait → stop VM
  status.sh                      — JSON status output for CLI and web UI
  update.sh                      — Pull latest image + redownload game
  backup.sh                      — Download world save tarball from GCP server
  restore.sh                     — Restore world from backup
  teardown.sh                    — Destroy all GCP resources (with confirmation)
  fetch-gportals-backup.sh       — Download latest backup from Gportals FTP (Valheim only)
  export-world.sh                — Export local Valheim world to backup format (Valheim only)
  update-modifiers.sh            — Change difficulty settings (Valheim only)
  games/
    valheim.sh                   — Valheim game config
    minecraft.sh                 — Minecraft game config
    7dtd.sh                      — 7 Days to Die game config
    enshrouded.sh                — Enshrouded game config
docs/
  valheim.md                     — Valheim configuration & world modifiers
  minecraft.md                   — Minecraft configuration
  7dtd.md                        — 7 Days to Die configuration
  enshrouded.md                  — Enshrouded configuration
web/
  app.py                         — Flask web UI backend
  templates/index.html           — Single-page web UI
  requirements.txt               — Python dependencies (flask)
```

## .env File
The `./bifrost` CLI auto-sources `.env` from the repo root. Required/optional variables:
```bash
GCP_PROJECT="your-project-id"                      # Required — no hardcoded default
FTP_URL="ftp://username:password@host:port"         # Optional — for Gportals FTP backup fetching
```

## Valheim Server Essentials
- UDP ports 2456-2458 must be open (firewall rule) — 2458 is used by Steam
- Players connect on port **2456** (not 2457)
- `SERVER_PASS` must be >= 5 characters
- First boot downloads ~1.9GB from Steam (takes 5-8 min)
- Subsequent boots take 2-4 min (world generation only, no Steam download)
- **Ready signal**: `Registering lobby` / `Opened Steam server` in Docker logs
  - `Game server connected` is NOT the ready signal — world gen still in progress
- Server needs ~2-4GB RAM for a small group
- World saves are in `/config/worlds/` inside the container
- Graceful shutdown: must allow save to complete before VM stops

## COS Gotchas
- Container-Optimized OS has a **read-only root filesystem** — cannot mkdir under `/mnt`
- Each game uses its own data mount path (e.g., `/var/valheim`, `/var/minecraft`)
- `gcloud compute instances create-with-container` is **deprecated** — use a startup-script instead
- Re-run startup script on a live VM: `sudo google_metadata_script_runner startup`
- **Race condition on boot**: After VM creation, SSH may be available before the startup script mounts the data disk. Always wait for `mountpoint -q <GAME_DATA_MOUNT>` before writing to the data disk.

## Startup Script & Metadata
- Server config is baked into the VM startup script metadata via `generate_startup_script()` in config.sh
- Changing WORLD_NAME (Valheim) requires updating metadata AND recreating the container (restore.sh handles this automatically)
- The startup script reuses existing containers (`docker start`) — only creates new ones on first boot
- To force a fresh container (e.g., after image update): remove container, then re-run startup script

## Commands
All commands accept `--game=valheim|minecraft|7dtd|enshrouded` (default: valheim).

- `./bifrost [--game=GAME] setup [--size=small|medium] [--restore=path/to/backup.tar.gz]` — One-time infrastructure setup
- `./bifrost [--game=GAME] start` — Start server, wait for ready, print connection IP
- `./bifrost [--game=GAME] stop` — Save and stop server
- `./bifrost [--game=GAME] status` — Show server status (JSON output)
- `./bifrost [--game=GAME] update` — Pull latest image + redownload game files
- `./bifrost [--game=GAME] backup` — Download world backup from GCP server
- `./bifrost [--game=GAME] restore [path/to/backup.tar.gz]` — Restore world from backup
- `./bifrost [--game=GAME] teardown` — Delete all GCP resources

Valheim-only commands:
- `./bifrost fetch-gportals <world-name>` — Download latest backup from Gportals FTP
- `./bifrost export-world [path/to/worlds]` — Export local Valheim world to backup format
- `./bifrost update-modifiers [--combat=X] [--preset=Y] ...` — Change difficulty settings

Local testing with Docker Compose:
- `docker compose --profile valheim up`
- `docker compose --profile minecraft up`

Web UI:
- `cd web && pip install -r requirements.txt && python app.py`
- Open `http://localhost:5000`

## Style & Conventions
- Shell scripts: `#!/usr/bin/env bash` with `set -euo pipefail`
- All sensitive config via gcloud instance metadata (never hardcode passwords)
- Scripts should be idempotent where possible
- Print clear status messages (what's happening, connection info)
- Game-specific logic goes in `scripts/games/<game>.sh`, not in the shared scripts
- Keep it simple — hobby project, not production infrastructure

## Cost Model
- Stopped: ~$0.40/mo per game (10GB disk only, free tier may cover it)
- Running (e2-small): ~$0.0168/hr + ~$0.005/hr (ephemeral IP)
- Running (e2-medium): ~$0.0336/hr + ~$0.005/hr (ephemeral IP)
- Typical month (20hrs play, one game): ~$0.84 (e2-small) or ~$1.17 (e2-medium)
