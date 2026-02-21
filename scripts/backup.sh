#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

STATUS=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --format='get(status)' 2>/dev/null) || true
if [ "$STATUS" != "RUNNING" ]; then
  echo "ERROR: $GAME_DISPLAY_NAME server is not running (${STATUS:-not found}). Start it first to create a backup."
  exit 1
fi

BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/../backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Build backup filename — for Valheim, include world name from VM metadata
if [ "$GAME_ID" = "valheim" ]; then
  WORLD=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" \
    --format='get(metadata.items[0].value)' 2>/dev/null \
    | grep -oP 'WORLD_NAME="\K[^"]+' || true)
  BACKUP_FILE="${GAME_ID}-${WORLD:-Dedicated}-${TIMESTAMP}.tar.gz"
else
  BACKUP_FILE="${GAME_ID}-${TIMESTAMP}.tar.gz"
fi

mkdir -p "$BACKUP_DIR"

REMOTE_PATH="${GAME_DATA_MOUNT}/${GAME_WORLD_SUBDIR}"
echo "==> Streaming backup of $REMOTE_PATH from server..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --ssh-flag="-T" -- \
  "sudo tar cf - -C ${REMOTE_PATH}/ --exclude='*_backup_*' --exclude='*.old' ." \
  | gzip > "$BACKUP_DIR/$BACKUP_FILE"

echo ""
echo "==> Backup saved to $BACKUP_DIR/$BACKUP_FILE"
ls -lh "$BACKUP_DIR/$BACKUP_FILE"
