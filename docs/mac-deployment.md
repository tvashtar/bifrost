# Mac Deployment

Run the Bifrost web UI as a persistent background service on macOS using `launchd`.

## Prerequisites

- [uv](https://docs.astral.sh/uv/) installed (`~/.local/bin/uv`)
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) installed and authenticated
- `.env` configured at the repo root with `GCP_PROJECT`

## Quick Start

```bash
# 1. Copy the launch agent plist
cp docs/com.bifrost.web.plist ~/Library/LaunchAgents/

# 2. Edit paths if your repo isn't at ~/repos/bifrost
#    (WorkingDirectory and uv path)

# 3. Load the service
launchctl load ~/Library/LaunchAgents/com.bifrost.web.plist

# 4. Open the UI
open http://127.0.0.1:8080
```

## Managing the Service

```bash
# Stop
launchctl unload ~/Library/LaunchAgents/com.bifrost.web.plist

# Start
launchctl load ~/Library/LaunchAgents/com.bifrost.web.plist

# Check status
launchctl list | grep bifrost

# View logs
tail -f /tmp/bifrost-web.log /tmp/bifrost-web.err
```

## How It Works

The plist tells `launchd` to:

- Run `uv run python app.py` from the `web/` directory
- Start automatically on login (`RunAtLoad`)
- Restart automatically if it crashes (`KeepAlive`)
- Log stdout/stderr to `/tmp/bifrost-web.log` and `/tmp/bifrost-web.err`

Flask runs with `debug=True`, so it auto-reloads when you edit `.py` files — no need to restart the service during development.

The idle process uses negligible CPU and ~20-30MB of RAM.

## Plist Location

The plist file is included at `docs/com.bifrost.web.plist`. If your repo path or `uv` path differs from the defaults, edit the plist before loading:

- `WorkingDirectory` — path to `bifrost/web/`
- `ProgramArguments` — first entry is the path to `uv`
- `PATH` in `EnvironmentVariables` — must include paths to `uv` and `gcloud` (launchd uses a minimal PATH by default)

## Troubleshooting

**Port 5000 already in use**: macOS Monterey+ uses port 8080 for AirPlay Receiver. Disable it in System Settings > General > AirDrop & Handoff > AirPlay Receiver, or change the port in `app.py`.

**gcloud errors**: Make sure `gcloud auth login` has been run and your `.env` has the correct `GCP_PROJECT`.
