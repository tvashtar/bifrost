#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/../backups}"

# Find the backup file — use argument or latest in backups/
if [ $# -ge 1 ]; then
  BACKUP_FILE="$1"
else
  BACKUP_FILE=$(ls -t "$BACKUP_DIR"/${GAME_ID}-*.tar.gz 2>/dev/null | head -1)
  if [ -z "$BACKUP_FILE" ]; then
    echo "ERROR: No backup files found in $BACKUP_DIR"
    echo "Usage: ./bifrost${GAME:+ --game=$GAME} restore [path/to/backup.tar.gz]"
    exit 1
  fi
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: Backup file not found: $BACKUP_FILE"
  exit 1
fi

# Detect world name from backup (Valheim-specific: .fwl files)
if [ "$GAME_ID" = "valheim" ]; then
  DETECTED_WORLD=$(tar tzf "$BACKUP_FILE" | grep -E '\.fwl$' | grep -v '_backup_' | head -1 | sed 's|.*/||; s|\.fwl$||')
  if [ -z "$DETECTED_WORLD" ]; then
    DETECTED_WORLD=$(tar tzf "$BACKUP_FILE" | grep -E '\.fwl$' | head -1 | sed 's|.*/||; s|\.fwl$||')
  fi
  if [ -n "$DETECTED_WORLD" ]; then
    echo "==> Detected world name: $DETECTED_WORLD"
    WORLD_NAME="$DETECTED_WORLD"
  else
    echo "==> No world files found in backup, using WORLD_NAME=$WORLD_NAME"
  fi
fi

echo "==> Restoring $GAME_DISPLAY_NAME from: $BACKUP_FILE"
echo "    This will overwrite the current world save on the server."
read -r -p "    Proceed? Type 'yes': " confirm
if [ "$confirm" != "yes" ]; then
  echo "Aborted."
  exit 1
fi

# Ensure VM is running
STATUS=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --format='get(status)')
if [ "$STATUS" != "RUNNING" ]; then
  echo "==> VM is not running. Starting it..."
  gcloud compute instances start "$VM_NAME" --zone="$ZONE" --quiet
  sleep 10
fi

echo "==> Stopping $GAME_DISPLAY_NAME container..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  "docker stop $GAME_CONTAINER_NAME 2>/dev/null || true"

echo "==> Uploading backup..."
gcloud compute scp "$BACKUP_FILE" "$VM_NAME:/tmp/${GAME_ID}-restore.tar.gz" \
  --zone="$ZONE" --quiet

echo "==> Extracting backup to data disk..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  "sudo mkdir -p $GAME_DATA_MOUNT/$GAME_WORLD_SUBDIR && sudo tar xzf /tmp/${GAME_ID}-restore.tar.gz -C $GAME_DATA_MOUNT/$GAME_WORLD_SUBDIR/ && rm -f /tmp/${GAME_ID}-restore.tar.gz"

# For Valheim: check if WORLD_NAME changed — if so, recreate container with new metadata
NEEDS_RECREATE=false
if [ "$GAME_ID" = "valheim" ]; then
  CURRENT_WORLD=$(gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
    "docker inspect $GAME_CONTAINER_NAME --format='{{range .Config.Env}}{{println .}}{{end}}'" 2>/dev/null \
    | grep '^WORLD_NAME=' | cut -d= -f2)
  if [ "$WORLD_NAME" != "$CURRENT_WORLD" ]; then
    echo "==> World name changed ($CURRENT_WORLD → $WORLD_NAME), updating server config..."
    NEEDS_RECREATE=true
  fi
fi

if [ "$NEEDS_RECREATE" = true ]; then
  # Update startup script metadata with new config
  STARTUP_FILE=$(mktemp)
  trap 'rm -f "$STARTUP_FILE"' EXIT
  generate_startup_script "$STARTUP_FILE"

  gcloud compute instances add-metadata "$VM_NAME" --zone="$ZONE" \
    --metadata-from-file=startup-script="$STARTUP_FILE"

  # Recreate container with new config
  gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
    "docker rm $GAME_CONTAINER_NAME && sudo google_metadata_script_runner startup"
else
  echo "==> Starting $GAME_DISPLAY_NAME container..."
  gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
    "docker start $GAME_CONTAINER_NAME"
fi

echo "==> Waiting for server to be ready..."
POLL_INTERVAL=5
BOOT_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
elapsed=0
while [ $elapsed -lt $GAME_READY_TIMEOUT ]; do
  if gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --command \
    "docker logs --since '$BOOT_TS' $GAME_CONTAINER_NAME 2>&1 | grep -q '$GAME_READY_SIGNAL'" 2>/dev/null; then
    IP=$(gcloud compute instances describe "$VM_NAME" \
      --zone="$ZONE" \
      --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    echo ""
    echo "==> Restore complete! Server is ready."
    echo "    Connect to $GAME_DISPLAY_NAME: $IP:$GAME_CONNECT_PORT"
    echo ""
    exit 0
  fi

  sleep $POLL_INTERVAL
  elapsed=$((elapsed + POLL_INTERVAL))
  if (( elapsed % 30 == 0 )); then
    echo "    ... still waiting (${elapsed}s elapsed)"
  fi
done

echo ""
echo "==> Timed out waiting for readiness. Check logs manually."
