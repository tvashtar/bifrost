#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Usage info
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Update world modifiers for the Valheim server.
Works whether the server is running or stopped.
World saves are NOT affected - only the difficulty settings change.

Options:
  --combat=VALUE           veryeasy, easy, hard, veryhard
  --deathpenalty=VALUE     casual, veryeasy, easy, hard, hardcore
  --resources=VALUE        muchless, less, more, muchmore, most
  --raids=VALUE            none, muchless, less, more, muchmore
  --portals=VALUE          casual, hard, veryhard
  --preset=VALUE           casual, easy, normal, hard, hardcore, immersive, hammer

  --list                   Show current world modifiers (no changes)
  --reset                  Clear all modifiers (use default/normal difficulty)
  -h, --help               Show this help

Examples:
  $0 --preset=casual
  $0 --combat=hard --resources=more
  $0 --reset

Notes:
  - If the server is running, it will be stopped and restarted (~3-5 minutes)
  - If the server is stopped, metadata is updated for the next start
  - Consider running './bifrost backup' first
  - Only specify modifiers you want to change
EOF
  exit 0
}

# Parse arguments
LIST_ONLY=false
RESET_MODIFIERS=false
UPDATE_COMBAT=""
UPDATE_DEATHPENALTY=""
UPDATE_RESOURCES=""
UPDATE_RAIDS=""
UPDATE_PORTALS=""
UPDATE_PRESET=""

for arg in "$@"; do
  case $arg in
    --combat=*)
      UPDATE_COMBAT="${arg#*=}"
      ;;
    --deathpenalty=*)
      UPDATE_DEATHPENALTY="${arg#*=}"
      ;;
    --resources=*)
      UPDATE_RESOURCES="${arg#*=}"
      ;;
    --raids=*)
      UPDATE_RAIDS="${arg#*=}"
      ;;
    --portals=*)
      UPDATE_PORTALS="${arg#*=}"
      ;;
    --preset=*)
      UPDATE_PRESET="${arg#*=}"
      ;;
    --list)
      LIST_ONLY=true
      ;;
    --reset)
      RESET_MODIFIERS=true
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $arg"
      usage
      ;;
  esac
done

# Check if any modifiers specified (skip for --list)
if [ "$LIST_ONLY" = false ] && \
   [ "$RESET_MODIFIERS" = false ] && \
   [ -z "$UPDATE_COMBAT" ] && \
   [ -z "$UPDATE_DEATHPENALTY" ] && \
   [ -z "$UPDATE_RESOURCES" ] && \
   [ -z "$UPDATE_RAIDS" ] && \
   [ -z "$UPDATE_PORTALS" ] && \
   [ -z "$UPDATE_PRESET" ]; then
  echo "Error: No modifiers specified"
  usage
fi

# Read current config from VM metadata (works regardless of VM state)
read_config_from_metadata() {
  echo "==> Reading current configuration from VM metadata..."
  local startup_script
  startup_script=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" \
    --format='value(metadata.items[startup-script])' 2>/dev/null) || {
    echo "ERROR: Could not read VM metadata. Is the VM set up?"
    exit 1
  }

  # Parse -e KEY="VAL" patterns from the startup script
  parse_env() {
    local key="$1"
    echo "$startup_script" | grep -oP " -e ${key}=\"\K[^\"]*" || echo ""
  }

  SERVER_NAME=$(parse_env "SERVER_NAME")
  SERVER_PASS=$(parse_env "SERVER_PASS")
  WORLD_NAME=$(parse_env "WORLD_NAME")
  SERVER_PUBLIC=$(parse_env "SERVER_PUBLIC")
  CURRENT_COMBAT=$(parse_env "MODIFIER_COMBAT")
  CURRENT_DEATHPENALTY=$(parse_env "MODIFIER_DEATHPENALTY")
  CURRENT_RESOURCES=$(parse_env "MODIFIER_RESOURCES")
  CURRENT_RAIDS=$(parse_env "MODIFIER_RAIDS")
  CURRENT_PORTALS=$(parse_env "MODIFIER_PORTALS")
  CURRENT_PRESET=$(parse_env "MODIFIER_PRESET")
}

# Get VM status (RUNNING, TERMINATED, STAGING, etc.)
get_vm_status() {
  gcloud compute instances describe "$VM_NAME" --zone="$ZONE" \
    --format='get(status)' 2>/dev/null || echo "UNKNOWN"
}

read_config_from_metadata
VM_STATUS=$(get_vm_status)

# Read modifiers from the .fwl world file via SSH (running VM only).
# The world file is the source of truth since Valheim bakes modifiers in.
read_modifiers_from_world_file() {
  local world_file="${GAME_DATA_MOUNT}/${GAME_WORLD_SUBDIR}/${WORLD_NAME}.fwl"
  local preset_line
  preset_line=$(gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
    "sudo cat $world_file 2>/dev/null | tr -cd '[:print:]\n' | grep -oE 'preset [a-z_:]+' | tail -1" 2>/dev/null) || true

  if [ -n "$preset_line" ]; then
    CURRENT_COMBAT=$(echo "$preset_line" | grep -o 'combat_[^:]*' | cut -d_ -f2 || echo "")
    CURRENT_DEATHPENALTY=$(echo "$preset_line" | grep -o 'deathpenalty_[^:]*' | cut -d_ -f2 || echo "")
    CURRENT_RESOURCES=$(echo "$preset_line" | grep -o 'resources_[^:]*' | cut -d_ -f2 || echo "")
    CURRENT_RAIDS=$(echo "$preset_line" | grep -o 'raids_[^:]*' | cut -d_ -f2 || echo "")
    CURRENT_PORTALS=$(echo "$preset_line" | grep -o 'portals_[^:]*' | cut -d_ -f2 || echo "")
    return 0
  fi
  return 1
}

# Read modifiers from local cache file (fallback when VM is stopped)
read_modifiers_from_cache() {
  local cache_file="$CACHE_DIR/${GAME_ID}-modifiers.json"
  if [ -f "$cache_file" ]; then
    local json
    json=$(cat "$cache_file")
    # Parse simple {"key":"val"} JSON — empty string if key missing
    parse_cache() {
      echo "$json" | grep -oP "\"$1\":\\s*\"\\K[^\"]*" || echo ""
    }
    CURRENT_COMBAT=$(parse_cache "combat")
    CURRENT_DEATHPENALTY=$(parse_cache "deathpenalty")
    CURRENT_RESOURCES=$(parse_cache "resources")
    CURRENT_RAIDS=$(parse_cache "raids")
    CURRENT_PORTALS=$(parse_cache "portals")
    CURRENT_PRESET=$(parse_cache "preset")
    return 0
  fi
  return 1
}

# Resolve current modifiers: world file (running) > cache (stopped) > metadata
if [ "$VM_STATUS" = "RUNNING" ]; then
  echo "==> Reading modifiers from world file..."
  read_modifiers_from_world_file || echo "    (Could not read world file, using metadata values)"
else
  # VM is stopped — can't SSH, so use cache (last known good from world file)
  if read_modifiers_from_cache; then
    echo "==> Using cached modifiers (from last server run)"
  else
    echo "==> No cached modifiers found, using metadata values"
  fi
fi

# If --list, just print current settings and exit
if [ "$LIST_ONLY" = true ]; then
  if [ "$VM_STATUS" = "RUNNING" ]; then
    local_source="world file"
  elif [ -f "$CACHE_DIR/${GAME_ID}-modifiers.json" ]; then
    local_source="cache"
  else
    local_source="VM metadata"
  fi

  echo ""
  echo "==> Server: $SERVER_NAME"
  echo "    World: $WORLD_NAME"
  echo ""
  echo "==> Current modifiers (from ${local_source}):"
  echo "    COMBAT: ${CURRENT_COMBAT:-default}"
  echo "    DEATHPENALTY: ${CURRENT_DEATHPENALTY:-default}"
  echo "    RESOURCES: ${CURRENT_RESOURCES:-default}"
  echo "    RAIDS: ${CURRENT_RAIDS:-default}"
  echo "    PORTALS: ${CURRENT_PORTALS:-default}"
  echo "    PRESET: ${CURRENT_PRESET:-default}"

  write_modifiers_cache \
    "combat=${CURRENT_COMBAT:-}" \
    "deathpenalty=${CURRENT_DEATHPENALTY:-}" \
    "resources=${CURRENT_RESOURCES:-}" \
    "raids=${CURRENT_RAIDS:-}" \
    "portals=${CURRENT_PORTALS:-}" \
    "preset=${CURRENT_PRESET:-}"

  exit 0
fi

# Set modifiers (use updates if provided, otherwise keep current)
if [ "$RESET_MODIFIERS" = true ]; then
  MODIFIER_COMBAT=""
  MODIFIER_DEATHPENALTY=""
  MODIFIER_RESOURCES=""
  MODIFIER_RAIDS=""
  MODIFIER_PORTALS=""
  MODIFIER_PRESET=""
  echo "==> Resetting all modifiers to default (normal difficulty)"
else
  MODIFIER_COMBAT="${UPDATE_COMBAT:-$CURRENT_COMBAT}"
  MODIFIER_DEATHPENALTY="${UPDATE_DEATHPENALTY:-$CURRENT_DEATHPENALTY}"
  MODIFIER_RESOURCES="${UPDATE_RESOURCES:-$CURRENT_RESOURCES}"
  MODIFIER_RAIDS="${UPDATE_RAIDS:-$CURRENT_RAIDS}"
  MODIFIER_PORTALS="${UPDATE_PORTALS:-$CURRENT_PORTALS}"
  MODIFIER_PRESET="${UPDATE_PRESET:-$CURRENT_PRESET}"
fi

# Show what will change
echo ""
echo "==> Server configuration:"
echo "    SERVER_NAME: $SERVER_NAME"
echo "    WORLD_NAME: $WORLD_NAME"
echo ""
echo "==> New modifiers:"
echo "    COMBAT: ${MODIFIER_COMBAT:-default}"
echo "    DEATHPENALTY: ${MODIFIER_DEATHPENALTY:-default}"
echo "    RESOURCES: ${MODIFIER_RESOURCES:-default}"
echo "    RAIDS: ${MODIFIER_RAIDS:-default}"
echo "    PORTALS: ${MODIFIER_PORTALS:-default}"
echo "    PRESET: ${MODIFIER_PRESET:-default}"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# Generate new startup script using shared function
echo "==> Generating new startup script with updated modifiers..."
STARTUP_FILE=$(mktemp)
trap 'rm -f "$STARTUP_FILE"' EXIT
generate_startup_script "$STARTUP_FILE"

# Update VM metadata
echo "==> Updating VM startup script..."
gcloud compute instances add-metadata "$VM_NAME" \
  --zone="$ZONE" \
  --metadata-from-file=startup-script="$STARTUP_FILE"

if [ "$VM_STATUS" = "RUNNING" ]; then
  # VM is running: remove old container and restart
  echo "==> Removing old container..."
  gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
    "docker rm -f $GAME_CONTAINER_NAME 2>/dev/null || true"

  echo "==> Starting server with new modifiers..."
  "$SCRIPT_DIR/start.sh"

  echo ""
  echo "==> Modifiers updated successfully!"
  echo "==> Server is starting with new difficulty settings."
else
  # VM is stopped: just update metadata
  echo ""
  echo "==> Modifiers updated successfully!"
  echo "==> Changes will take effect next time the server starts."
fi

# Cache the new modifiers locally
write_modifiers_cache \
  "combat=${MODIFIER_COMBAT:-}" \
  "deathpenalty=${MODIFIER_DEATHPENALTY:-}" \
  "resources=${MODIFIER_RESOURCES:-}" \
  "raids=${MODIFIER_RAIDS:-}" \
  "portals=${MODIFIER_PORTALS:-}" \
  "preset=${MODIFIER_PRESET:-}"
