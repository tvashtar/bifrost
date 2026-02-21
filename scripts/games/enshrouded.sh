#!/usr/bin/env bash
# Game config: Enshrouded

GAME_ID="enshrouded"
GAME_DISPLAY_NAME="Enshrouded"

# GCP resource names
VM_NAME="bifrost-enshrouded"
DISK_NAME="bifrost-enshrouded-data"
FIREWALL_RULE="bifrost-allow-enshrouded"
NETWORK_TAG="enshrouded-server"

# Docker
GAME_IMAGE="mornedhels/enshrouded-server:latest"
GAME_CONTAINER_NAME="enshrouded-server"

# Ports
GAME_PORTS_DOCKER=("15636-15637:15636-15637/udp")
GAME_PORTS_FIREWALL="udp:15636-15637"

# VM sizing
GAME_DEFAULT_SIZE="e2-medium"
GAME_MIN_SIZE="e2-medium"

# Ready signal
GAME_READY_SIGNAL="HostOnline"
GAME_READY_TIMEOUT=900
GAME_BOOT_MESSAGE="First boot downloads ~3GB — this takes 8-15 min."

# Data paths
GAME_DATA_MOUNT="/var/enshrouded"
GAME_DATA_VOLUME="/opt/enshrouded"
GAME_WORLD_SUBDIR="savegame"

# Connection
GAME_CONNECT_PORT="15637"

# Container
GAME_STOP_TIMEOUT=90
GAME_DOCKER_EXTRA=""

# Enshrouded config defaults
ENSHROUDED_SLOTS="${ENSHROUDED_SLOTS:-16}"
SERVER_NAME="${SERVER_NAME:-Bifrost Enshrouded}"
SERVER_PASS="${SERVER_PASS:-}"

game_docker_env_flags() {
  echo " -e SERVER_NAME=\"$SERVER_NAME\""
  echo " -e SERVER_SLOT_COUNT=\"$ENSHROUDED_SLOTS\""
  [ -n "$SERVER_PASS" ] && echo " -e SERVER_PASSWORD=\"$SERVER_PASS\""
  echo " -e PUID=1000"
  echo " -e PGID=1000"
}

game_validate_config() {
  if [ "$MACHINE_TYPE" = "e2-small" ] && [ -z "${FORCE_SMALL:-}" ]; then
    echo "WARNING: Enshrouded needs at least 4GB RAM (e2-medium)."
    echo "    Overriding to e2-medium. Set FORCE_SMALL=1 to force e2-small."
    MACHINE_TYPE="e2-medium"
  fi
}
