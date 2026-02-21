# Valheim

Docker image: [lloesche/valheim-server-docker](https://github.com/lloesche/valheim-server-docker)

## Quick Start

```bash
SERVER_PASS='yourpass' ./bifrost setup
./bifrost start
```

Players connect on UDP port **2456**.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `SERVER_NAME` | `"Bifrost"` | Server name shown in browser |
| `SERVER_PASS` | *required* | Password (min 5 chars) |
| `WORLD_NAME` | `"Dedicated"` | World file name |
| `SERVER_PUBLIC` | `false` | List in public server browser |

See the full list of environment variables at [lloesche/valheim-server-docker](https://github.com/lloesche/valheim-server-docker#environment-variables).

## World Modifiers

```bash
# Set during setup
MODIFIER_PRESET=casual SERVER_PASS='yourpass' ./bifrost setup

# Change on existing world
./bifrost update-modifiers --preset=casual
./bifrost update-modifiers --raids=muchless --resources=more
./bifrost update-modifiers --list    # View current
./bifrost update-modifiers --reset   # Back to defaults
```

| Variable | Values |
|---|---|
| `MODIFIER_PRESET` | `casual`, `easy`, `hard`, `hardcore`, `immersive`, `hammer` |
| `MODIFIER_COMBAT` | `veryeasy`, `easy`, `hard`, `veryhard` |
| `MODIFIER_DEATHPENALTY` | `casual`, `veryeasy`, `easy`, `hard`, `hardcore` |
| `MODIFIER_RESOURCES` | `muchless`, `less`, `more`, `muchmore`, `most` |
| `MODIFIER_RAIDS` | `none`, `muchless`, `less`, `more`, `muchmore` |
| `MODIFIER_PORTALS` | `casual`, `hard`, `veryhard` |

## Valheim-Only Commands

```bash
./bifrost export-world                 # Export local Valheim world to backup format
./bifrost fetch-gportals <world-name>  # Download backup from Gportals FTP
./bifrost update-modifiers [flags]     # Change world difficulty
```

### Gportals FTP

To fetch backups from a Gportals server, add to your `.env`:

```bash
FTP_URL="ftp://username:password@host:port"
```

Then: `./bifrost fetch-gportals <world-name>` (e.g., `./bifrost fetch-gportals Finnland`)

## Notes

- First boot downloads ~1.9GB from Steam (5-8 min). Subsequent boots take 2-4 min.
- UDP ports 2456-2458 must be open — 2458 is used by Steam.
- `SERVER_PASS` must be at least 5 characters.
- World saves are in `/config/worlds_local/` inside the container.
