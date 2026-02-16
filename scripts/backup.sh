#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/../backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="valheim-backup-$TIMESTAMP.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "==> Creating backup archive on server..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  'sudo tar czf /tmp/valheim-backup.tar.gz -C /mnt/disks/gce-containers-mounts/gce-persistent-disks/valserver-data/ .'

echo "==> Downloading backup..."
gcloud compute scp "$VM_NAME:/tmp/valheim-backup.tar.gz" "$BACKUP_DIR/$BACKUP_FILE" \
  --zone="$ZONE" --quiet

echo "==> Cleaning up remote temp file..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  'rm -f /tmp/valheim-backup.tar.gz'

echo ""
echo "==> Backup saved to $BACKUP_DIR/$BACKUP_FILE"
ls -lh "$BACKUP_DIR/$BACKUP_FILE"
