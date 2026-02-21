# 7 Days to Die

Docker image: [vinanrra/7dtd-server-docker](https://github.com/vinanrra/7dtd-server-docker)

## Quick Start

```bash
./bifrost --game=7dtd setup
./bifrost --game=7dtd start
```

Players connect on UDP port **26900**.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `SERVER_NAME` | `"Bifrost 7DTD"` | Server name |
| `SDTD_VERSION` | `stable` | Game version (`stable` or specific build) |

See the full list of environment variables at [vinanrra/7dtd-server-docker](https://github.com/vinanrra/7dtd-server-docker#parameters).

## VM Sizing

7DTD requires at least **e2-medium** (4GB RAM). If you pass `--size=small`, setup will warn and auto-upgrade:

```
WARNING: 7 Days to Die needs at least 4GB RAM (e2-medium).
    Overriding to e2-medium. Set FORCE_SMALL=1 to force e2-small.
```

## Notes

- First boot downloads ~3GB and generates the world (8-15 min).
- Ports: UDP 26900-26902, TCP 26900.
- World saves are in `/home/sdtdserver/.local/share/7DaysToDie/Saves/` inside the container.
