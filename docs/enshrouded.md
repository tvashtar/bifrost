# Enshrouded

Docker image: [mornedhels/enshrouded-server](https://github.com/mornedhels/enshrouded-server)

## Quick Start

```bash
./bifrost --game=enshrouded setup
./bifrost --game=enshrouded start
```

Players connect on UDP port **15637**.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `SERVER_NAME` | `"Bifrost Enshrouded"` | Server name |
| `SERVER_PASS` | *(none)* | Server password (optional) |
| `ENSHROUDED_SLOTS` | `16` | Max player slots |

See the full list of environment variables at [mornedhels/enshrouded-server](https://github.com/mornedhels/enshrouded-server#environment-variables).

## VM Sizing

Enshrouded requires at least **e2-medium** (4GB RAM). If you pass `--size=small`, setup will warn and auto-upgrade:

```
WARNING: Enshrouded needs at least 4GB RAM (e2-medium).
    Overriding to e2-medium. Set FORCE_SMALL=1 to force e2-small.
```

## Notes

- First boot downloads ~3GB (8-15 min).
- Ports: UDP 15636-15637.
- World saves are in `/opt/enshrouded/savegame/` inside the container.
