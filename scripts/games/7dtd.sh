#!/usr/bin/env bash
# Game config: 7 Days to Die

GAME_ID="7dtd"
GAME_DISPLAY_NAME="7 Days to Die"

# GCP resource names
VM_NAME="bifrost-7dtd"
DISK_NAME="bifrost-7dtd-data"
FIREWALL_RULE="bifrost-allow-7dtd"
NETWORK_TAG="sdtd-server"

# Docker
GAME_IMAGE="vinanrra/7dtd-server:latest"
GAME_CONTAINER_NAME="7dtd-server"

# Ports
GAME_PORTS_DOCKER=("26900-26902:26900-26902/udp" "26900:26900/tcp")
GAME_PORTS_FIREWALL="udp:26900-26902,tcp:26900"

# VM sizing
GAME_DEFAULT_SIZE="e2-medium"
GAME_MIN_SIZE="e2-medium"
GAME_DISK_SIZE=15  # 7DTD needs ~12GB for game files

# Ready signal
GAME_READY_SIGNAL="GameServer.Init successful"
GAME_READY_TIMEOUT=900
GAME_BOOT_MESSAGE="First boot downloads ~3GB and generates world — this takes 8-15 min."

# Data paths
GAME_DATA_MOUNT="/var/7dtd"
GAME_DATA_VOLUME="/home/sdtdserver/.local/share/7DaysToDie"
GAME_WORLD_SUBDIR="Saves"

# Connection
GAME_CONNECT_PORT="26900"

# Container
GAME_STOP_TIMEOUT=60
GAME_DOCKER_EXTRA=""

# 7DTD config defaults
SDTD_VERSION="${SDTD_VERSION:-stable}"
SERVER_NAME="${SERVER_NAME:-Bifrost 7DTD}"

game_docker_env_flags() {
  echo " -e START_MODE=1"
  echo " -e VERSION=\"$SDTD_VERSION\""
  echo " -e PUID=1000"
  echo " -e PGID=1000"
}

game_validate_config() {
  if [ "$MACHINE_TYPE" = "e2-small" ] && [ -z "${FORCE_SMALL:-}" ]; then
    echo "WARNING: 7 Days to Die needs at least 4GB RAM (e2-medium)."
    echo "    Overriding to e2-medium. Set FORCE_SMALL=1 to force e2-small."
    MACHINE_TYPE="e2-medium"
  fi
}
