#!/usr/bin/env bash
# Shared configuration for all valserver scripts.
# Override any of these with environment variables before running.

PROJECT="${GCP_PROJECT:-valserver-487600}"
ZONE="${GCP_ZONE:-us-east4-c}"
REGION="${GCP_REGION:-us-east4}"

VM_NAME="valserver"
MACHINE_TYPE="e2-small"
DISK_NAME="valserver-data"
DISK_SIZE="10"  # GB
FIREWALL_RULE="valserver-allow-valheim"
NETWORK_TAG="valheim-server"

# Valheim server config defaults
SERVER_NAME="${SERVER_NAME:-Valserver}"
SERVER_PASS="${SERVER_PASS:-}"
WORLD_NAME="${WORLD_NAME:-Dedicated}"
SERVER_PUBLIC="${SERVER_PUBLIC:-false}"

# World modifiers (set at world creation — changing on existing worlds may not take effect)
# Leave empty for default/normal. See: https://github.com/lloesche/valheim-server-docker#world-modifiers
MODIFIER_COMBAT="${MODIFIER_COMBAT:-}"           # veryeasy, easy, hard, veryhard
MODIFIER_DEATHPENALTY="${MODIFIER_DEATHPENALTY:-}" # casual, veryeasy, easy, hard, hardcore
MODIFIER_RESOURCES="${MODIFIER_RESOURCES:-}"       # muchless, less, more, muchmore, most
MODIFIER_RAIDS="${MODIFIER_RAIDS:-}"               # none, muchless, less, more, muchmore
MODIFIER_PORTALS="${MODIFIER_PORTALS:-}"           # casual, hard, veryhard
MODIFIER_PRESET="${MODIFIER_PRESET:-}"             # casual, easy, normal, hard, hardcore, immersive, hammer

# Docker image — pin to a specific tag for reproducibility
VALHEIM_IMAGE="lloesche/valheim-server:latest"
