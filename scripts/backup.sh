#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/../backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Get the world name from the Docker container
echo "==> Fetching world name from server..."
WORLD_NAME=$(gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  'docker inspect valheim-server --format="{{range .Config.Env}}{{println .}}{{end}}"' 2>/dev/null \
  | grep '^WORLD_NAME=' | cut -d= -f2 || echo "Dedicated")

# Fallback to "Dedicated" if not found
WORLD_NAME="${WORLD_NAME:-Dedicated}"

BACKUP_FILE="${WORLD_NAME}-${TIMESTAMP}.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "==> Creating backup archive on server..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  'sudo tar czf /tmp/valheim-backup.tar.gz -C /var/valheim/ .'

echo "==> Downloading backup..."
gcloud compute scp "$VM_NAME:/tmp/valheim-backup.tar.gz" "$BACKUP_DIR/$BACKUP_FILE" \
  --zone="$ZONE" --quiet

echo "==> Cleaning up remote temp file..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  'sudo rm -f /tmp/valheim-backup.tar.gz'

echo ""
echo "==> Backup saved to $BACKUP_DIR/$BACKUP_FILE"
ls -lh "$BACKUP_DIR/$BACKUP_FILE"
