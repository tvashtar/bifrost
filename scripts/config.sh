#!/usr/bin/env bash
# Shared configuration for all bifrost scripts.
# Override any of these with environment variables before running.

# GCP project settings (same for all games)
PROJECT="${GCP_PROJECT:-valserver-487600}"
ZONE="${GCP_ZONE:-us-east4-c}"
REGION="${GCP_REGION:-us-east4}"
DISK_SIZE="${DISK_SIZE:-10}"  # GB

# Game selection: default to valheim for backwards compatibility
GAME="${GAME:-valheim}"

# Resolve game config
GAMES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/games"
GAME_CONFIG="$GAMES_DIR/${GAME}.sh"

if [ ! -f "$GAME_CONFIG" ]; then
  echo "ERROR: Unknown game '$GAME'. Available games:"
  for f in "$GAMES_DIR"/*.sh; do
    echo "  - $(basename "$f" .sh)"
  done
  exit 1
fi

source "$GAME_CONFIG"

# Machine type: use game default unless overridden by env or --size flag
MACHINE_TYPE="${MACHINE_TYPE:-$GAME_DEFAULT_SIZE}"

# Generate the startup script that runs on the GCP VM.
# Called by setup.sh and restore.sh to avoid duplicating the heredoc.
# Usage: generate_startup_script "/path/to/output/file"
generate_startup_script() {
  local outfile="$1"

  # Build env flags as a space-separated string (one long line is fine)
  local env_flags
  env_flags=$(game_docker_env_flags | tr '\n' ' ')

  # Build port flags
  local port_flags=""
  for p in "${GAME_PORTS_DOCKER[@]}"; do
    port_flags+=" -p $p"
  done

  # Unquoted heredoc: variables expand, \$ becomes $, \newline is consumed.
  # The docker run command ends up as one long line — that's fine.
  cat > "$outfile" <<EOF
#!/bin/bash
set -e

DATA_DEV="/dev/disk/by-id/google-${DISK_NAME}"
DATA_MNT="${GAME_DATA_MOUNT}"

# Format the data disk if it has no filesystem
if ! blkid "\$DATA_DEV" &>/dev/null; then
  echo "Formatting data disk..."
  mkfs.ext4 -m 0 -F -E lazy_itable_init=0 "\$DATA_DEV"
fi

# Mount the data disk
mkdir -p "\$DATA_MNT"
mount -o discard,defaults "\$DATA_DEV" "\$DATA_MNT" || true

# Start existing container, or create a new one on first boot
if docker container inspect ${GAME_CONTAINER_NAME} &>/dev/null; then
  echo "Starting existing ${GAME_DISPLAY_NAME} container..."
  docker start ${GAME_CONTAINER_NAME}
else
  echo "First boot — pulling image and creating container..."
  docker pull ${GAME_IMAGE}
  docker run -d \
    --name ${GAME_CONTAINER_NAME} \
    --restart unless-stopped \
    --stop-timeout ${GAME_STOP_TIMEOUT} \
    ${GAME_DOCKER_EXTRA} \
    ${port_flags} \
    ${env_flags} \
    -v "\$DATA_MNT:${GAME_DATA_VOLUME}" \
    ${GAME_IMAGE}
fi
EOF
}
