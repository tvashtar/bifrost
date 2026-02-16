# valserver

A quick-deploy Valheim dedicated server on GCP Compute Engine — cheap to run, easy to spin up and tear down.

## Why GCP Compute Engine?

| Requirement | GCP Compute Engine | Fly.io | Railway |
|---|---|---|---|
| UDP support | Native | Yes (dedicated IPv4 required) | **No** (dealbreaker) |
| Pay only when running | Yes (stopped VMs = disk only) | Partially (volume + rootfs billed) | N/A |
| Docker support | Yes (Container-Optimized OS) | Yes | Yes |
| Persistent storage | Persistent Disk (survives stop) | Volumes | Volumes |
| CLI management | `gcloud` | `flyctl` | `railway` |
| **~Cost at 20hrs/mo** | **~$0.84** (ephemeral IP) | ~$3.80-5 | N/A |

**Railway** was ruled out (no inbound UDP). **Fly.io** works but costs more due to mandatory dedicated IPv4 ($2/mo) for UDP. GCP Compute Engine is the cheapest option — stopped VMs only bill for disk (~$0.40/mo for 10GB), and ephemeral IPs cost nearly nothing.

## Architecture

```
┌──────────────────────────────────────┐
│     GCP Compute Engine (e2-small)    │
│  ┌────────────────────────────────┐  │
│  │  Container-Optimized OS (COS)  │  │
│  │  ┌──────────────────────────┐  │  │
│  │  │ lloesche/valheim-server  │  │  │
│  │  │ - Auto-updates Valheim   │  │  │
│  │  │ - World backups          │  │  │
│  │  │ - BepInEx/mod support    │  │  │
│  │  └──────────────────────────┘  │  │
│  └────────────────────────────────┘  │
│         │                            │
│         ▼                            │
│  ┌──────────────┐                    │
│  │ Persistent   │  World saves,      │
│  │ Disk /config │  backups, config   │
│  └──────────────┘                    │
└──────────────────────────────────────┘
        │ UDP 2456-2458
        ▼
   Players connect via ephemeral IP
```

## Prerequisites

- [gcloud CLI](https://cloud.google.com/sdk/docs/install) installed and authenticated
- A GCP project with billing enabled
- Docker (for local testing only)

## Quick Start

### 1. Initial Setup

```bash
# Clone and enter the repo
git clone <this-repo>
cd valserver

# Set your GCP project
export GCP_PROJECT="your-project-id"
gcloud config set project $GCP_PROJECT

# Run the setup script (creates VM, firewall rules, disk)
./val setup
```

### 2. Connect

Start the server and wait for it to be ready:

```bash
./val start
# Polls server logs and prints the IP when actually ready to accept connections
```

In Valheim: **Join Game → Add Server → `<ip>:2456`**

> **Note**: First boot takes 5-8 min (downloads ~1.9GB from Steam + world generation). Subsequent boots take 2-4 min (world generation only). The script waits for the server to be fully ready before printing the connection info.

> **Note**: The IP changes each time you start the server (ephemeral). The start script prints it. If you want a fixed IP, see [Static IP](#optional-static-ip) below.

### 3. Update (after a Valheim patch)

```bash
./val update
# Pulls latest Docker image, redownloads game files, waits for ready
```

World saves are preserved — only the server binary is refreshed.

### 4. Stop / Start (save money)

```bash
# Stop the server (only disk billed while stopped — ~$0.40/mo)
./val stop

# Start it back up for game night
./val start
```

### 5. Tear Down Completely

```bash
# Download your world save first
./val backup

# Destroy everything
./val teardown
```

## Configuration

Server config is set via instance metadata (passed as env vars to the container). Key settings:

| Variable | Default | Description |
|---|---|---|
| `SERVER_NAME` | `"My Server"` | Server name shown in browser |
| `SERVER_PASS` | *required* | Password (min 5 chars) |
| `WORLD_NAME` | `"Dedicated"` | World file name |
| `SERVER_PUBLIC` | `false` | List in public server browser |
| `BACKUPS_CRON` | `*/15 * * * *` | Backup frequency |

See the full list at [lloesche/valheim-server-docker](https://github.com/lloesche/valheim-server-docker#environment-variables).

To update config:

```bash
gcloud compute instances add-metadata valserver \
  --metadata SERVER_NAME="New Name"
```

## Cost Breakdown

For a small friend group playing ~20 hours/month:

| Resource | Cost | Notes |
|---|---|---|
| Compute (e2-small) | ~$0.34 | $0.0168/hr × 20hrs |
| Persistent Disk (10GB) | ~$0.40 | Billed 24/7, free tier covers it |
| Ephemeral IP | ~$0.10 | Only while running |
| **Total** | **~$0.84/mo** | |

With a static IP instead: ~$4.72/mo ($3.65/mo for reserved IP).

Compare to $5-15/month for always-on game hosting.

## Optional: Static IP

If you want a consistent server address:

```bash
gcloud compute addresses create valserver-ip --region <your-region>
# Then update scripts/setup.sh to use --address=valserver-ip
```

This adds ~$3.65/mo but means the same IP every session.

## Local Testing

```bash
docker compose up
```

Connect to `localhost:2456` from Valheim.

## Project Structure

```
valserver/
├── val                     # CLI entry point (./val start, ./val stop, etc.)
├── docker-compose.yml      # Local development/testing
├── scripts/
│   ├── config.sh           # Shared config (project, zone, VM name, etc.)
│   ├── setup.sh            # One-time: create VM, firewall, disk
│   ├── start.sh            # Start VM, wait for ready, print IP
│   ├── stop.sh             # Graceful save + stop VM
│   ├── update.sh           # Pull latest image + redownload game files
│   ├── backup.sh           # Download world save locally
│   └── teardown.sh         # Destroy all GCP resources
├── CLAUDE.md
└── README.md
```

## Troubleshooting

- **"Connection failed"**: Server takes 2-4 min to boot (5-8 min on first start, which downloads ~1.9GB from Steam). The `start.sh` script waits for the `Registering lobby` log line before printing "ready". If you started manually, check `gcloud compute ssh valserver -- 'docker logs valheim-server'`.
- **"Password too short"**: `SERVER_PASS` must be at least 5 characters.
- **World data lost**: Ensure the persistent disk is mounted and the Docker volume maps to it.
- **Performance issues**: Resize with `gcloud compute instances set-machine-type valserver --machine-type e2-standard-2`.
- **IP changed**: Expected with ephemeral IPs. Run `./val start` to see the new one.

## Sources

- [lloesche/valheim-server-docker](https://github.com/lloesche/valheim-server-docker) — Docker image
- [Valheim Dedicated Server Guide](https://www.valheimgame.com/support/a-guide-to-dedicated-servers/) — Official docs
- [GCP Compute Engine Pricing](https://cloud.google.com/compute/all-pricing) — VM and disk costs
- [GCP VM Lifecycle](https://cloud.google.com/compute/docs/instances/instance-life-cycle) — Stop/start billing
- [GCP Container-Optimized OS](https://cloud.google.com/container-optimized-os/docs) — Docker on GCE
