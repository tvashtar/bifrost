# Minecraft

Docker image: [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server)

## Quick Start

```bash
./bifrost --game=minecraft setup
./bifrost --game=minecraft start
```

Players connect on TCP port **25565**.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `SERVER_NAME` | `"Bifrost Minecraft"` | Server name |
| `MC_DIFFICULTY` | `normal` | `peaceful`, `easy`, `normal`, `hard` |
| `MC_GAMEMODE` | `survival` | `survival`, `creative`, `adventure`, `spectator` |
| `MC_MEMORY` | `2G` | JVM memory allocation |
| `MC_MOTD` | `"A Bifrost Minecraft Server"` | Message of the day |
| `MC_OPS` | *(none)* | Comma-separated list of op usernames |

See the full list of environment variables at [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server#server-configuration).

## Notes

- First boot downloads server files (3-5 min).
- EULA is auto-accepted.
- World saves are in `/data/world/` inside the container.
