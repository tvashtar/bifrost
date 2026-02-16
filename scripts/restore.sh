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
  'sudo tar xzf /tmp/valheim-restore.tar.gz -C /var/valheim/ && rm -f /tmp/valheim-restore.tar.gz'

echo "==> Starting Valheim container..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  'docker start valheim-server'

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
