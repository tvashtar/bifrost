#!/usr/bin/env bash
# Game config: Minecraft

GAME_ID="minecraft"
GAME_DISPLAY_NAME="Minecraft"

# GCP resource names
VM_NAME="bifrost-minecraft"
DISK_NAME="bifrost-minecraft-data"
FIREWALL_RULE="bifrost-allow-minecraft"
NETWORK_TAG="minecraft-server"

# Docker
GAME_IMAGE="itzg/minecraft-server:latest"
GAME_CONTAINER_NAME="minecraft-server"

# Ports
GAME_PORTS_DOCKER=("25565:25565/tcp")
GAME_PORTS_FIREWALL="tcp:25565"

# VM sizing
GAME_DEFAULT_SIZE="e2-small"
GAME_MIN_SIZE=""  # e2-small is fine for vanilla

# Ready signal
GAME_READY_SIGNAL="Done ("
GAME_READY_TIMEOUT=600
GAME_BOOT_MESSAGE="First boot downloads server files — this takes 3-5 min."

# Data paths
GAME_DATA_MOUNT="/var/minecraft"
GAME_DATA_VOLUME="/data"
GAME_WORLD_SUBDIR="world"

# Connection
GAME_CONNECT_PORT="25565"

# Container
GAME_STOP_TIMEOUT=30
GAME_DOCKER_EXTRA=""

# Minecraft server config defaults
MC_DIFFICULTY="${MC_DIFFICULTY:-normal}"
MC_GAMEMODE="${MC_GAMEMODE:-survival}"
MC_MEMORY="${MC_MEMORY:-2G}"
MC_MOTD="${MC_MOTD:-A Bifrost Minecraft Server}"
MC_OPS="${MC_OPS:-}"
SERVER_NAME="${SERVER_NAME:-Bifrost Minecraft}"

game_docker_env_flags() {
  echo " -e EULA=TRUE"
  echo " -e SERVER_NAME=\"$SERVER_NAME\""
  echo " -e DIFFICULTY=\"$MC_DIFFICULTY\""
  echo " -e GAMEMODE=\"$MC_GAMEMODE\""
  echo " -e MEMORY=\"$MC_MEMORY\""
  echo " -e MOTD=\"$MC_MOTD\""
  [ -n "$MC_OPS" ] && echo " -e OPS=\"$MC_OPS\""
}

game_validate_config() {
  # No strict requirements — EULA is auto-accepted in env flags
  return 0
}
