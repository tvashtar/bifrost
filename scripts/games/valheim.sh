#!/usr/bin/env bash
# Game config: Valheim

GAME_ID="valheim"
GAME_DISPLAY_NAME="Valheim"

# GCP resource names
VM_NAME="valserver"
DISK_NAME="valserver-data"
FIREWALL_RULE="valserver-allow-valheim"
NETWORK_TAG="valheim-server"

# Docker
GAME_IMAGE="lloesche/valheim-server:latest"
GAME_CONTAINER_NAME="valheim-server"

# Ports
GAME_PORTS_DOCKER=("2456-2458:2456-2458/udp")
GAME_PORTS_FIREWALL="udp:2456-2458"

# VM sizing
GAME_DEFAULT_SIZE="e2-small"
GAME_MIN_SIZE=""  # e2-small is fine

# Ready signal (grep pattern in docker logs)
GAME_READY_SIGNAL="Registering lobby"
GAME_READY_TIMEOUT=900  # 15 min for first boot (Steam download)
GAME_BOOT_MESSAGE="First boot downloads ~1.9GB from Steam — this takes 5-8 min."

# Data paths
GAME_DATA_MOUNT="/var/valheim"
GAME_DATA_VOLUME="/config"
GAME_WORLD_SUBDIR="worlds_local"

# Connection
GAME_CONNECT_PORT="2456"

# Container
GAME_STOP_TIMEOUT=30
GAME_DOCKER_EXTRA="--cap-add SYS_NICE"

# Valheim server config defaults
SERVER_NAME="${SERVER_NAME:-Bifrost}"
SERVER_PASS="${SERVER_PASS:-}"
WORLD_NAME="${WORLD_NAME:-Dedicated}"
SERVER_PUBLIC="${SERVER_PUBLIC:-false}"

# World modifiers
MODIFIER_COMBAT="${MODIFIER_COMBAT:-}"
MODIFIER_DEATHPENALTY="${MODIFIER_DEATHPENALTY:-}"
MODIFIER_RESOURCES="${MODIFIER_RESOURCES:-}"
MODIFIER_RAIDS="${MODIFIER_RAIDS:-}"
MODIFIER_PORTALS="${MODIFIER_PORTALS:-}"
MODIFIER_PRESET="${MODIFIER_PRESET:-}"

game_docker_env_flags() {
  echo " -e SERVER_NAME=\"$SERVER_NAME\""
  echo " -e SERVER_PASS=\"$SERVER_PASS\""
  echo " -e WORLD_NAME=\"$WORLD_NAME\""
  echo " -e SERVER_PUBLIC=\"$SERVER_PUBLIC\""
  echo " -e BACKUPS_CRON=\"*/15 * * * *\""
  echo " -e BACKUPS_MAX_COUNT=5"
  [ -n "$MODIFIER_COMBAT" ]       && echo " -e MODIFIER_COMBAT=\"$MODIFIER_COMBAT\"" || true
  [ -n "$MODIFIER_DEATHPENALTY" ] && echo " -e MODIFIER_DEATHPENALTY=\"$MODIFIER_DEATHPENALTY\"" || true
  [ -n "$MODIFIER_RESOURCES" ]    && echo " -e MODIFIER_RESOURCES=\"$MODIFIER_RESOURCES\"" || true
  [ -n "$MODIFIER_RAIDS" ]        && echo " -e MODIFIER_RAIDS=\"$MODIFIER_RAIDS\"" || true
  [ -n "$MODIFIER_PORTALS" ]      && echo " -e MODIFIER_PORTALS=\"$MODIFIER_PORTALS\"" || true
  [ -n "$MODIFIER_PRESET" ]       && echo " -e MODIFIER_PRESET=\"$MODIFIER_PRESET\"" || true
}

game_validate_config() {
  if [ -z "${SERVER_PASS:-}" ]; then
    echo "ERROR: SERVER_PASS must be set (min 5 characters)."
    echo "Usage: SERVER_PASS='yourpass' ./bifrost setup [--size=small|medium]"
    return 1
  fi
  if [ ${#SERVER_PASS} -lt 5 ]; then
    echo "ERROR: SERVER_PASS must be at least 5 characters."
    return 1
  fi
}
