# CLAUDE.md — valserver

## Project Overview
Valheim dedicated server on GCP Compute Engine using Docker. Designed for cheap pay-per-use hosting with easy stop/start for casual play sessions.

## Tech Stack
- **GCP Compute Engine**: e2-medium VM with Container-Optimized OS (COS)
- **Docker**: `lloesche/valheim-server-docker` image (pin to specific tag)
- **gcloud CLI**: All infrastructure management
- **Bash scripts**: Convenience wrappers for setup/start/stop/backup/teardown

## Key Decisions
- **GCP over Fly.io**: Cheaper (~$1.17/mo vs ~$4/mo) because stopped VMs only bill for disk, and ephemeral IPs are nearly free
- **GCP over Railway**: Railway has no inbound UDP support (Valheim requires UDP 2456-2457)
- **Ephemeral IP by default**: Saves ~$3.50/mo vs static IP. IP changes on restart but start script prints it
- **Container-Optimized OS**: Preinstalled Docker, minimal attack surface, auto-updates
- **lloesche/valheim-server-docker**: Auto-updates Valheim, world backups, mod support, actively maintained

## GCP Resources Created
- `valserver` — e2-medium Compute Engine VM (Container-Optimized OS)
- `valserver-disk` — 10GB pd-standard persistent disk for world saves
- `valserver-firewall` — Firewall rule allowing UDP 2456-2458 ingress

## File Layout
```
docker-compose.yml      — Local testing
scripts/
  setup.sh              — One-time GCP resource creation (VM, disk, firewall)
  start.sh              — Start VM, wait for healthy, print IP
  stop.sh               — Graceful save → wait → stop VM
  backup.sh             — Download world save tarball locally
  teardown.sh           — Destroy all GCP resources (with confirmation)
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
- Use `/var/valheim` for the data disk mount point (writable)
- `gcloud compute instances create-with-container` is **deprecated** — use a startup-script instead
- Re-run startup script on a live VM: `sudo google_metadata_script_runner startup`

## Commands
- `./scripts/setup.sh` — One-time infrastructure setup
- `./scripts/start.sh` — Start server, print connection IP
- `./scripts/stop.sh` — Save and stop server
- `./scripts/backup.sh` — Download world backup
- `./scripts/teardown.sh` — Delete all GCP resources
- `docker compose up` — Run locally for testing

## Style & Conventions
- Shell scripts: `#!/usr/bin/env bash` with `set -euo pipefail`
- All sensitive config via gcloud instance metadata (never hardcode passwords)
- Scripts should be idempotent where possible
- Print clear status messages (what's happening, connection info)
- Keep it simple — hobby project, not production infrastructure

## Cost Model
- Stopped: ~$0.40/mo (10GB disk only, free tier may cover it)
- Running: ~$0.0335/hr (e2-medium) + ~$0.005/hr (ephemeral IP)
- Typical month (20hrs play): ~$1.17
