# bifrost

Multi-game dedicated server manager on GCP Compute Engine — cheap pay-per-use hosting for Valheim, Minecraft, 7 Days to Die, and Enshrouded.

## Supported Games

| Game | Docker Image | Ports | Default VM | Min VM |
|------|-------------|-------|-----------|--------|
| Valheim | `lloesche/valheim-server` | UDP 2456-2458 | e2-small (2GB) | e2-small |
| Minecraft | `itzg/minecraft-server` | TCP 25565 | e2-small (2GB) | e2-small |
| 7 Days to Die | `vinanrra/7dtd-server` | UDP 26900-26902, TCP 26900 | e2-medium (4GB) | e2-medium |
| Enshrouded | `mornedhels/enshrouded-server` | UDP 15636-15637 | e2-medium (4GB) | e2-medium |

## Why GCP Compute Engine?

| Requirement | GCP Compute Engine | Fly.io | Railway |
|---|---|---|---|
| UDP support | Native | Yes (dedicated IPv4 required) | **No** (dealbreaker) |
| Pay only when running | Yes (stopped VMs = disk only) | Partially (volume + rootfs billed) | N/A |
| Docker support | Yes (Container-Optimized OS) | Yes | Yes |
| **~Cost at 20hrs/mo** | **~$0.84** (e2-small) | ~$3.80-5 | N/A |

Stopped VMs only bill for disk (~$0.40/mo for 10GB). Ephemeral IPs cost nearly nothing.

## Prerequisites

- [gcloud CLI](https://cloud.google.com/sdk/docs/install) installed and authenticated
- A GCP project with billing enabled
- Docker (for local testing only)
- [uv](https://docs.astral.sh/uv/) (for web UI only)

## Quick Start

```bash
git clone git@github.com:tvashtar/bifrost.git
cd bifrost

# Create .env with your GCP project ID
cat > .env <<'EOF'
GCP_PROJECT="your-project-id"
EOF

# Set up a Valheim server
SERVER_PASS='yourpass' ./bifrost setup

# Set up a Minecraft server
./bifrost --game=minecraft setup

# Set up a 7DTD server (auto-uses e2-medium)
./bifrost --game=7dtd setup

# Start and connect
./bifrost start                        # Valheim (default)
./bifrost --game=minecraft start       # Minecraft
```

The `.env` file is sourced automatically by `./bifrost` and is gitignored.

## Commands

All commands accept `--game=valheim|minecraft|7dtd|enshrouded` (default: `valheim`).

```bash
./bifrost [--game=GAME] setup [--size=small|medium] [--restore=backup.tar.gz]
./bifrost [--game=GAME] start          # Start server, wait for ready, print IP
./bifrost [--game=GAME] stop           # Graceful save + stop VM
./bifrost [--game=GAME] status         # Show server status (JSON)
./bifrost [--game=GAME] backup         # Download world backup
./bifrost [--game=GAME] restore [file] # Restore world from backup
./bifrost [--game=GAME] update         # Pull latest image + redownload game
./bifrost [--game=GAME] teardown       # Delete all GCP resources
```

Valheim-only commands:
```bash
./bifrost export-world                 # Export local Valheim world
./bifrost fetch-gportals <world-name>  # Download backup from Gportals FTP
./bifrost update-modifiers [flags]     # Change world difficulty
```

## Web UI

A basic local web UI for managing all game servers:

```bash
cd web
uv run app.py
# Open http://localhost:5000
```

Shows status, start/stop/backup buttons for all 4 games in a dark-themed dashboard.

## Local Testing

```bash
docker compose --profile valheim up
docker compose --profile minecraft up
docker compose --profile 7dtd up
docker compose --profile enshrouded up
```

## Game Configuration

Each game has its own configuration variables, VM requirements, and notes:

- [Valheim](docs/valheim.md) — world modifiers, Gportals FTP, password setup
- [Minecraft](docs/minecraft.md) — difficulty, gamemode, ops, memory
- [7 Days to Die](docs/7dtd.md) — requires e2-medium (4GB RAM)
- [Enshrouded](docs/enshrouded.md) — requires e2-medium (4GB RAM)

## Cost Breakdown

For ~20 hours/month of play per game:

| | e2-small (Valheim, MC) | e2-medium (7DTD, Enshrouded) |
|---|---|---|
| Compute | ~$0.34 | ~$0.67 |
| Disk (10GB) | ~$0.40 | ~$0.40 |
| Ephemeral IP | ~$0.10 | ~$0.10 |
| **Total** | **~$0.84/mo** | **~$1.17/mo** |

Compare to $5-15/month for always-on game hosting.

## Architecture

Each game gets its own set of GCP resources:

| Game | VM | Disk | Firewall Rule |
|------|-----|------|---------------|
| Valheim | `bifrost` | `bifrost-data` | `bifrost-allow-valheim` |
| Minecraft | `bifrost-minecraft` | `bifrost-minecraft-data` | `bifrost-allow-minecraft` |
| 7DTD | `bifrost-7dtd` | `bifrost-7dtd-data` | `bifrost-allow-7dtd` |
| Enshrouded | `bifrost-enshrouded` | `bifrost-enshrouded-data` | `bifrost-allow-enshrouded` |

Game-specific config lives in `scripts/games/<game>.sh`. Shared logic (GCP project, startup script generation) is in `scripts/config.sh`. The `bifrost` CLI parses `--game=` and exports the `GAME` env var to all scripts.

## Troubleshooting

- **"Connection failed"**: Server takes 2-8 min to boot depending on game. The start script waits for the ready signal before printing "ready".
- **"Password too short"** (Valheim): `SERVER_PASS` must be at least 5 characters.
- **IP changed**: Expected with ephemeral IPs. Run `./bifrost start` to see the new one.
- **Performance issues**: Resize with `gcloud compute instances set-machine-type <vm-name> --machine-type e2-standard-2`.
- **Check logs**: `gcloud compute ssh <vm-name> --zone=us-east4-c -- 'docker logs -f <container-name>'`

## Optional: Static IP

```bash
gcloud compute addresses create bifrost-ip --region <your-region>
# Then update scripts/setup.sh to use --address=bifrost-ip
```

Adds ~$3.65/mo but gives a consistent server address.

## Sources

- [lloesche/valheim-server-docker](https://github.com/lloesche/valheim-server-docker)
- [itzg/minecraft-server](https://github.com/itzg/docker-minecraft-server)
- [vinanrra/7dtd-server](https://github.com/vinanrra/7dtd-server-docker)
- [mornedhels/enshrouded-server](https://github.com/mornedhels/enshrouded-server)
- [GCP Compute Engine Pricing](https://cloud.google.com/compute/all-pricing)
