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

# Build backup filename — for Valheim, include world name
if [ "$GAME_ID" = "valheim" ]; then
  echo "==> Fetching world name from server..."
  WORLD_NAME=$(gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
    "docker inspect $GAME_CONTAINER_NAME --format='{{range .Config.Env}}{{println .}}{{end}}'" 2>/dev/null \
    | grep '^WORLD_NAME=' | cut -d= -f2 || echo "Dedicated")
  WORLD_NAME="${WORLD_NAME:-Dedicated}"
  BACKUP_FILE="${GAME_ID}-${WORLD_NAME}-${TIMESTAMP}.tar.gz"
else
  BACKUP_FILE="${GAME_ID}-${TIMESTAMP}.tar.gz"
fi

mkdir -p "$BACKUP_DIR"

echo "==> Streaming backup from server (tar on remote, gzip locally)..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  "sudo tar cf - -C ${GAME_DATA_MOUNT}/ ." \
  | gzip > "$BACKUP_DIR/$BACKUP_FILE"

echo ""
echo "==> Backup saved to $BACKUP_DIR/$BACKUP_FILE"
ls -lh "$BACKUP_DIR/$BACKUP_FILE"
