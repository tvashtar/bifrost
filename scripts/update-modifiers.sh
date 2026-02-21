#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Usage info
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Update world modifiers on the running Valheim server.
World saves are NOT affected - only the difficulty settings change.

Options:
  --combat=VALUE           veryeasy, easy, hard, veryhard
  --deathpenalty=VALUE     casual, veryeasy, easy, hard, hardcore
  --resources=VALUE        muchless, less, more, muchmore, most
  --raids=VALUE            none, muchless, less, more, muchmore
  --portals=VALUE          casual, hard, veryhard
  --preset=VALUE           casual, easy, normal, hard, hardcore, immersive, hammer

  --list                   Show actual world modifiers from .fwl file (no changes)
  --reset                  Clear all modifiers (use default/normal difficulty)
  -h, --help               Show this help

Examples:
  $0 --preset=casual
  $0 --combat=hard --resources=more
  $0 --reset

Notes:
  - Server will be stopped and restarted (takes ~3-5 minutes)
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

# Get current values from running container
echo "==> Fetching current server configuration..."
CURRENT_ENV=$(gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  'docker inspect valheim-server --format="{{range .Config.Env}}{{println .}}{{end}}"' 2>/dev/null)

get_env_var() {
  local var_name="$1"
  echo "$CURRENT_ENV" | grep "^${var_name}=" | cut -d= -f2 || echo ""
}

SERVER_NAME=$(get_env_var "SERVER_NAME")
SERVER_PASS=$(get_env_var "SERVER_PASS")
WORLD_NAME=$(get_env_var "WORLD_NAME" | tr -d '\r\n' | xargs)
SERVER_PUBLIC=$(get_env_var "SERVER_PUBLIC")

# If --list, just print current settings and exit
if [ "$LIST_ONLY" = true ]; then
  echo ""
  echo "==> Server: $SERVER_NAME"
  echo "    World: $WORLD_NAME"
  echo ""
  echo "==> Reading actual world modifiers from .fwl file..."

  # Extract modifiers from the world file
  WORLD_FILE="/var/valheim/worlds_local/${WORLD_NAME}.fwl"
  PRESET_LINE=$(gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
    "sudo cat $WORLD_FILE 2>/dev/null | tr -cd '[:print:]\n' | grep -oE 'preset [a-z_:]+' | tail -1" || echo "")

  if [ -z "$PRESET_LINE" ]; then
    echo "    (Could not read world file - showing container env vars instead)"
    CURRENT_COMBAT=$(get_env_var "MODIFIER_COMBAT")
    CURRENT_DEATHPENALTY=$(get_env_var "MODIFIER_DEATHPENALTY")
    CURRENT_RESOURCES=$(get_env_var "MODIFIER_RESOURCES")
    CURRENT_RAIDS=$(get_env_var "MODIFIER_RAIDS")
    CURRENT_PORTALS=$(get_env_var "MODIFIER_PORTALS")
    CURRENT_PRESET=$(get_env_var "MODIFIER_PRESET")

    echo ""
    echo "==> Container env modifiers:"
    echo "    COMBAT: ${CURRENT_COMBAT:-default}"
    echo "    DEATHPENALTY: ${CURRENT_DEATHPENALTY:-default}"
    echo "    RESOURCES: ${CURRENT_RESOURCES:-default}"
    echo "    RAIDS: ${CURRENT_RAIDS:-default}"
    echo "    PORTALS: ${CURRENT_PORTALS:-default}"
    echo "    PRESET: ${CURRENT_PRESET:-default}"
  else
    # Parse the preset line (format: "preset combat_X:deathpenalty_Y:resources_Z:raids_W:portals_V")
    CURRENT_COMBAT=$(echo "$PRESET_LINE" | grep -o 'combat_[^:]*' | cut -d_ -f2 || echo "default")
    CURRENT_DEATHPENALTY=$(echo "$PRESET_LINE" | grep -o 'deathpenalty_[^:]*' | cut -d_ -f2 || echo "default")
    CURRENT_RESOURCES=$(echo "$PRESET_LINE" | grep -o 'resources_[^:]*' | cut -d_ -f2 || echo "default")
    CURRENT_RAIDS=$(echo "$PRESET_LINE" | grep -o 'raids_[^:]*' | cut -d_ -f2 || echo "default")
    CURRENT_PORTALS=$(echo "$PRESET_LINE" | grep -o 'portals_[^:]*' | cut -d_ -f2 || echo "default")

    echo ""
    echo "==> Active world modifiers (from .fwl file):"
    echo "    COMBAT: $CURRENT_COMBAT"
    echo "    DEATHPENALTY: $CURRENT_DEATHPENALTY"
    echo "    RESOURCES: $CURRENT_RESOURCES"
    echo "    RAIDS: $CURRENT_RAIDS"
    echo "    PORTALS: $CURRENT_PORTALS"
  fi

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
  MODIFIER_COMBAT="${UPDATE_COMBAT:-$(get_env_var "MODIFIER_COMBAT")}"
  MODIFIER_DEATHPENALTY="${UPDATE_DEATHPENALTY:-$(get_env_var "MODIFIER_DEATHPENALTY")}"
  MODIFIER_RESOURCES="${UPDATE_RESOURCES:-$(get_env_var "MODIFIER_RESOURCES")}"
  MODIFIER_RAIDS="${UPDATE_RAIDS:-$(get_env_var "MODIFIER_RAIDS")}"
  MODIFIER_PORTALS="${UPDATE_PORTALS:-$(get_env_var "MODIFIER_PORTALS")}"
  MODIFIER_PRESET="${UPDATE_PRESET:-$(get_env_var "MODIFIER_PRESET")}"
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

# Stop the server gracefully
echo ""
echo "==> Stopping server gracefully..."
"$SCRIPT_DIR/stop.sh"

# Generate new startup script
echo "==> Generating new startup script with updated modifiers..."
STARTUP_FILE=$(mktemp)
trap 'rm -f "$STARTUP_FILE"' EXIT

cat > "$STARTUP_FILE" <<'STARTUP_EOF'
#!/bin/bash
set -e

# Wait for data disk to be available
echo "Waiting for data disk mount..."
timeout=60
while [ $timeout -gt 0 ] && ! mountpoint -q /var/valheim; do
  sleep 1
  ((timeout--))
done

if ! mountpoint -q /var/valheim; then
  echo "ERROR: Data disk not mounted at /var/valheim"
  exit 1
fi

# Start or create container
if docker ps -a --format '{{.Names}}' | grep -q '^valheim-server$'; then
  echo "Starting existing container..."
  docker start valheim-server
else
  echo "Creating new container..."
  docker run -d \
    --name valheim-server \
    --restart=unless-stopped \
    -v /var/valheim:/config \
STARTUP_EOF

# Add environment variables
cat >> "$STARTUP_FILE" <<ENV_EOF
    -p 2456-2458:2456-2458/udp \\
    -e SERVER_NAME="$SERVER_NAME" \\
    -e SERVER_PASS="$SERVER_PASS" \\
    -e WORLD_NAME="$WORLD_NAME" \\
    -e SERVER_PUBLIC="$SERVER_PUBLIC" \\
    -e BACKUPS_CRON="*/15 * * * *" \\
ENV_EOF

# Add modifiers (only if not empty)
if [ -n "$MODIFIER_COMBAT" ]; then
  echo "    -e MODIFIER_COMBAT=\"$MODIFIER_COMBAT\" \\" >> "$STARTUP_FILE"
fi
if [ -n "$MODIFIER_DEATHPENALTY" ]; then
  echo "    -e MODIFIER_DEATHPENALTY=\"$MODIFIER_DEATHPENALTY\" \\" >> "$STARTUP_FILE"
fi
if [ -n "$MODIFIER_RESOURCES" ]; then
  echo "    -e MODIFIER_RESOURCES=\"$MODIFIER_RESOURCES\" \\" >> "$STARTUP_FILE"
fi
if [ -n "$MODIFIER_RAIDS" ]; then
  echo "    -e MODIFIER_RAIDS=\"$MODIFIER_RAIDS\" \\" >> "$STARTUP_FILE"
fi
if [ -n "$MODIFIER_PORTALS" ]; then
  echo "    -e MODIFIER_PORTALS=\"$MODIFIER_PORTALS\" \\" >> "$STARTUP_FILE"
fi
if [ -n "$MODIFIER_PRESET" ]; then
  echo "    -e MODIFIER_PRESET=\"$MODIFIER_PRESET\" \\" >> "$STARTUP_FILE"
fi

# Finish startup script
cat >> "$STARTUP_FILE" <<'STARTUP_EOF'
    lloesche/valheim-server:latest
fi

echo "Valheim server startup complete"
STARTUP_EOF

# Update VM metadata
echo "==> Updating VM startup script..."
gcloud compute instances add-metadata "$VM_NAME" \
  --zone="$ZONE" \
  --metadata-from-file=startup-script="$STARTUP_FILE"

# Remove old container so it gets recreated with new config
echo "==> Removing old container..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  'docker rm -f valheim-server 2>/dev/null || true'

# Start the server
echo "==> Starting server with new modifiers..."
"$SCRIPT_DIR/start.sh"

echo ""
echo "==> Modifiers updated successfully!"
echo "==> Server is starting with new difficulty settings."
