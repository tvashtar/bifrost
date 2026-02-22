#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo "==> Updating $GAME_DISPLAY_NAME server (pulls latest image + re-downloads game files)..."

# Ensure VM is running
STATUS=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --format='get(status)')
if [ "$STATUS" != "RUNNING" ]; then
  echo "==> VM is not running. Starting it first..."
  gcloud compute instances start "$VM_NAME" --zone="$ZONE" --quiet
  echo "==> Waiting for VM to be ready..."
  wait_for_ssh
fi

IP=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo "==> Updating VM startup script metadata..."
STARTUP_FILE=$(mktemp)
generate_startup_script "$STARTUP_FILE"
gcloud compute instances add-metadata "$VM_NAME" --zone="$ZONE" \
  --metadata-from-file=startup-script="$STARTUP_FILE"
rm -f "$STARTUP_FILE"

echo "==> Removing old container and pulling latest image..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --command \
  "docker stop $GAME_CONTAINER_NAME 2>/dev/null || true && docker rm $GAME_CONTAINER_NAME 2>/dev/null || true"

# Capture timestamp before starting so we don't miss the ready signal
BOOT_TS=$(get_vm_timestamp)

# Re-run the startup script, which will see no container and create a fresh one
echo "==> Re-running startup script (fresh container)..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --command \
  'sudo google_metadata_script_runner startup'

echo "==> Waiting for $GAME_DISPLAY_NAME server to be ready..."

if wait_for_ready "$BOOT_TS" 5; then
  echo ""
  echo "==> Update complete! Server is ready."
  echo "    Connect to $GAME_DISPLAY_NAME: $IP:$GAME_CONNECT_PORT"
  echo ""
  exit 0
fi

echo ""
echo "==> Timed out waiting for readiness (server may still be updating)."
echo "    Connect to $GAME_DISPLAY_NAME: $IP:$GAME_CONNECT_PORT"
echo "    Check logs: gcloud compute ssh $VM_NAME --zone=$ZONE -- 'docker logs -f $GAME_CONTAINER_NAME'"
exit 1
