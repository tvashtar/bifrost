#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo "WARNING: This will permanently delete $GAME_DISPLAY_NAME resources:"
echo "  - VM: $VM_NAME"
echo "  - Disk: $DISK_NAME (all world saves!)"
echo "  - Firewall rule: $FIREWALL_RULE"
echo ""
read -r -p "Have you backed up your world saves? Type 'yes' to proceed: " confirm

if [ "$confirm" != "yes" ]; then
  echo "Aborted. Run ./bifrost${GAME:+ --game=$GAME} backup first."
  exit 1
fi

echo "==> Deleting VM..."
gcloud compute instances delete "$VM_NAME" \
  --zone="$ZONE" --quiet 2>/dev/null || echo "    (VM not found, skipping)"

echo "==> Deleting persistent disk..."
gcloud compute disks delete "$DISK_NAME" \
  --zone="$ZONE" --quiet 2>/dev/null || echo "    (disk not found, skipping)"

echo "==> Deleting firewall rule..."
gcloud compute firewall-rules delete "$FIREWALL_RULE" \
  --quiet 2>/dev/null || echo "    (firewall rule not found, skipping)"

echo ""
echo "==> All $GAME_DISPLAY_NAME resources deleted. No further charges will be incurred."
