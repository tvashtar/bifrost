#!/usr/bin/env bash
# Shared configuration for all bifrost scripts.
# Override any of these with environment variables before running.

# GCP project settings (same for all games)
PROJECT="${GCP_PROJECT:?GCP_PROJECT must be set in .env or environment}"
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

# Remember which variables the user set explicitly (shell env or .env) before
# the game config fills in defaults — see keep_from_metadata below.
_USER_ENV_VARS=" $(compgen -e | tr '\n' ' ') "

source "$GAME_CONFIG"

# Machine type: use game default unless overridden by env or --size flag
MACHINE_TYPE="${MACHINE_TYPE:-$GAME_DEFAULT_SIZE}"

# Fatal log pattern (grep -E): checked by wait_for_ready. Games may extend it.
GAME_FATAL_LOG_PATTERN="${GAME_FATAL_LOG_PATTERN:-No space left on device}"

# Disk size: use game-specific size if set, otherwise the global default
DISK_SIZE="${GAME_DISK_SIZE:-$DISK_SIZE}"

# Repo root (parent of scripts/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="$REPO_ROOT/.cache"

# Write modifier values to the local cache file.
# Usage: write_modifiers_cache key1=val1 key2=val2 ...
# Only non-empty values are written. Output is JSON matching the web API format.
write_modifiers_cache() {
  mkdir -p "$CACHE_DIR"
  local cache_file="$CACHE_DIR/${GAME_ID}-modifiers.json"
  local json="{"
  local first=true
  for pair in "$@"; do
    local key="${pair%%=*}"
    local val="${pair#*=}"
    val="${val%"${val##*[![:space:]]}"}"  # trim trailing whitespace
    if [ -n "$val" ] && [ "$val" != "default" ]; then
      $first || json+=","
      json+="\"$key\":\"$val\""
      first=false
    fi
  done
  json+="}"
  echo "$json" > "$cache_file"
}

# Load the server's current config (server name, password, world, modifiers...)
# from the VM's startup-script metadata, so regenerating the startup script
# doesn't silently reset it to defaults. Variables the user set explicitly in
# their environment still win. Each game maps its own variables in
# game_load_config_from_metadata().
# Usage: load_current_config  (returns 1 if the VM/metadata can't be read)
load_current_config() {
  STARTUP_METADATA=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" \
    --format='value(metadata.items[startup-script])' 2>/dev/null) || return 1
  [ -n "$STARTUP_METADATA" ] || return 1
  if declare -F game_load_config_from_metadata >/dev/null; then
    game_load_config_from_metadata
  fi
}

# Print the value of a docker `-e KEY="VAL"` flag from the loaded metadata.
metadata_env() {
  echo "$STARTUP_METADATA" | sed -n "s/.*-e $1=\"\([^\"]*\)\".*/\1/p" | tail -1
}

# Set VAR from the metadata's -e KEY (defaults to VAR), unless the user set VAR
# explicitly. Usage: keep_from_metadata VAR [KEY]
keep_from_metadata() {
  local var="$1" key="${2:-$1}"
  [[ "$_USER_ENV_VARS" == *" $var "* ]] && return 0
  printf -v "$var" '%s' "$(metadata_env "$key")"
}

# Wait for SSH and data disk to be ready on the VM.
# Usage: wait_for_ssh [max_attempts]  (default: 24 = 2 minutes)
wait_for_ssh() {
  local max_attempts="${1:-24}"
  for i in $(seq 1 "$max_attempts"); do
    if gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
      "mountpoint -q '$GAME_DATA_MOUNT'" 2>/dev/null; then
      return 0
    fi
    sleep 5
  done
  echo "ERROR: Timed out waiting for VM SSH/disk to be ready."
  return 1
}

# Get a UTC timestamp from the VM (avoids local clock skew).
# Falls back to local time if SSH fails.
get_vm_timestamp() {
  local ts
  ts=$(gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
    "date -u +%Y-%m-%dT%H:%M:%SZ" 2>/dev/null | tr -d '\r') || true
  if [ -z "$ts" ]; then
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  fi
  echo "$ts"
}

# Wait for the game server container to log the ready signal.
# Streams the latest log line each poll so the user can see progress.
# Usage: wait_for_ready <boot_timestamp> [poll_interval]
wait_for_ready() {
  local boot_ts="$1"
  local poll_interval="${2:-5}"
  local elapsed=0
  local last_line=""

  while [ $elapsed -lt $GAME_READY_TIMEOUT ]; do
    # Check ALL logs since boot for a fatal error or the ready signal (not just tail)
    local check
    check=$(gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --command \
      "logs=\$(docker logs --since '$boot_ts' '$GAME_CONTAINER_NAME' 2>&1); \
       echo \"\$logs\" | grep -E -m1 '$GAME_FATAL_LOG_PATTERN' | sed 's/^/FATAL: /'; \
       echo \"\$logs\" | grep -Fq '$GAME_READY_SIGNAL' && echo READY" 2>/dev/null) || true

    if echo "$check" | grep -q '^FATAL: '; then
      # Kill (not stop) so the server can't write a save from a broken install
      gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --command \
        "docker kill '$GAME_CONTAINER_NAME'" >/dev/null 2>&1 || true
      echo ""
      echo "ERROR: $GAME_DISPLAY_NAME server hit a fatal error. Container killed WITHOUT saving to protect the world:"
      echo "    $(echo "$check" | grep '^FATAL: ' | head -1 | sed 's/^FATAL: //' | sed 's/\x1b\[[0-9;]*m//g')"
      echo "    Check disk space: gcloud compute ssh $VM_NAME --zone=$ZONE -- 'df -h / /var/lib/docker $GAME_DATA_MOUNT'"
      exit 1
    fi
    if echo "$check" | grep -qx 'READY'; then
      return 0
    fi

    # Fetch recent lines, strip ANSI, pick the last meaningful one (has [tag])
    local recent
    recent=$(gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --command \
      "docker logs --since '$boot_ts' --tail 10 '$GAME_CONTAINER_NAME' 2>&1" 2>/dev/null | \
      sed 's/\x1b\[[0-9;]*m//g') || true
    local current_line
    current_line=$(echo "$recent" | grep '\[' | tail -1 | xargs)
    # Fall back to last non-empty line if no tagged lines found
    [ -z "$current_line" ] && current_line=$(echo "$recent" | sed '/^\s*$/d' | tail -1 | xargs)
    if [ -n "$current_line" ] && [ "$current_line" != "$last_line" ]; then
      echo "    [${elapsed}s] $current_line"
      last_line="$current_line"
    elif (( elapsed > 0 && elapsed % 30 == 0 )); then
      echo "    ... still waiting (${elapsed}s elapsed)"
    fi

    sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
  done

  return 1
}

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

# Stop container if auto-restarted before disk is mounted (race condition)
if docker container inspect "${GAME_CONTAINER_NAME}" &>/dev/null; then
  docker stop "${GAME_CONTAINER_NAME}" 2>/dev/null || true
fi

# Mount the data disk
mkdir -p "\$DATA_MNT"
mount -o discard,defaults "\$DATA_DEV" "\$DATA_MNT" || true

# Start existing container, or create a new one on first boot
if docker container inspect "${GAME_CONTAINER_NAME}" &>/dev/null; then
  echo "Starting existing ${GAME_DISPLAY_NAME} container..."
  docker start "${GAME_CONTAINER_NAME}"
else
  echo "First boot — pulling image and creating container..."
  docker pull "${GAME_IMAGE}"
  docker run -d \\
    --name "${GAME_CONTAINER_NAME}" \\
    --restart unless-stopped \\
    --stop-timeout ${GAME_STOP_TIMEOUT} \\
    ${GAME_DOCKER_EXTRA} \\
    ${port_flags} \\
    ${env_flags} \\
    -v "\$DATA_MNT:${GAME_DATA_VOLUME}" \\
    "${GAME_IMAGE}"
fi
EOF
}
