#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/../backups}"

# Find the backup file — use argument or latest in backups/
if [ $# -ge 1 ]; then
  BACKUP_FILE="$1"
else
  BACKUP_FILE=$(ls -t "$BACKUP_DIR"/valheim-backup-*.tar.gz 2>/dev/null | head -1)
  if [ -z "$BACKUP_FILE" ]; then
    echo "ERROR: No backup files found in $BACKUP_DIR"
    echo "Usage: ./val restore [path/to/backup.tar.gz]"
    exit 1
  fi
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: Backup file not found: $BACKUP_FILE"
  exit 1
fi

# Detect world name from backup (look for .fwl files, exclude auto-backups)
DETECTED_WORLD=$(tar tzf "$BACKUP_FILE" | grep -E '\.fwl$' | grep -v '_backup_' | head -1 | sed 's|.*/||; s|\.fwl$||')
if [ -z "$DETECTED_WORLD" ]; then
  # Fall back to any .fwl file
  DETECTED_WORLD=$(tar tzf "$BACKUP_FILE" | grep -E '\.fwl$' | head -1 | sed 's|.*/||; s|\.fwl$||')
fi

if [ -n "$DETECTED_WORLD" ]; then
  echo "==> Detected world name: $DETECTED_WORLD"
  WORLD_NAME="$DETECTED_WORLD"
else
  echo "==> No world files found in backup, using WORLD_NAME=$WORLD_NAME"
fi

echo "==> Restoring from: $BACKUP_FILE"
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

echo "==> Stopping Valheim container..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  'docker stop valheim-server 2>/dev/null || true'

echo "==> Uploading backup..."
gcloud compute scp "$BACKUP_FILE" "$VM_NAME:/tmp/valheim-restore.tar.gz" \
  --zone="$ZONE" --quiet

echo "==> Extracting backup to data disk..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  'sudo mkdir -p /var/valheim/worlds_local && sudo tar xzf /tmp/valheim-restore.tar.gz -C /var/valheim/worlds_local/ && rm -f /tmp/valheim-restore.tar.gz'

# Check if WORLD_NAME changed — if so, recreate container with new metadata
CURRENT_WORLD=$(gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  'docker inspect valheim-server --format="{{range .Config.Env}}{{println .}}{{end}}"' 2>/dev/null \
  | grep '^WORLD_NAME=' | cut -d= -f2)

if [ "$WORLD_NAME" != "$CURRENT_WORLD" ]; then
  echo "==> World name changed ($CURRENT_WORLD → $WORLD_NAME), updating server config..."

  # Update startup script metadata with new WORLD_NAME
  STARTUP_FILE=$(mktemp)
  trap 'rm -f "$STARTUP_FILE"' EXIT
  cat > "$STARTUP_FILE" <<EOF
#!/bin/bash
set -e

DATA_DEV="/dev/disk/by-id/google-valserver-data"
DATA_MNT="/var/valheim"

if ! blkid "\$DATA_DEV" &>/dev/null; then
  echo "Formatting data disk..."
  mkfs.ext4 -m 0 -F -E lazy_itable_init=0 "\$DATA_DEV"
fi

mkdir -p "\$DATA_MNT"
mount -o discard,defaults "\$DATA_DEV" "\$DATA_MNT" || true

if docker container inspect valheim-server &>/dev/null; then
  echo "Starting existing Valheim container..."
  docker start valheim-server
else
  echo "First boot — pulling image and creating container..."
  docker pull $VALHEIM_IMAGE
  docker run -d \
    --name valheim-server \
    --restart unless-stopped \
    --cap-add SYS_NICE \
    --stop-timeout 30 \
    -p 2456-2458:2456-2458/udp \
    -e SERVER_NAME="$SERVER_NAME" \
    -e SERVER_PASS="$SERVER_PASS" \
    -e WORLD_NAME="$WORLD_NAME" \
    -e SERVER_PUBLIC="$SERVER_PUBLIC" \
    -e BACKUPS_CRON="*/15 * * * *" \
    -v "\$DATA_MNT:/config" \
    $VALHEIM_IMAGE
fi
EOF
  gcloud compute instances add-metadata "$VM_NAME" --zone="$ZONE" \
    --metadata-from-file=startup-script="$STARTUP_FILE"

  # Recreate container with new WORLD_NAME
  gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
    'docker rm valheim-server && sudo google_metadata_script_runner startup'
else
  echo "==> Starting Valheim container..."
  gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
    'docker start valheim-server'
fi

echo "==> Waiting for server to be ready..."
READY_TIMEOUT=600
POLL_INTERVAL=5
BOOT_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
elapsed=0
while [ $elapsed -lt $READY_TIMEOUT ]; do
  if gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --command \
    "docker logs --since '$BOOT_TS' valheim-server 2>&1 | grep -q 'Registering lobby'" 2>/dev/null; then
    IP=$(gcloud compute instances describe "$VM_NAME" \
      --zone="$ZONE" \
      --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    echo ""
    echo "==> Restore complete! Server is ready."
    echo "    Connect in Valheim: $IP:2456"
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
