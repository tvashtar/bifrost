#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo "==> Updating Valheim server (pulls latest image + re-downloads game files)..."
echo "    This will take 5-8 min."

# Ensure VM is running
STATUS=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --format='get(status)')
if [ "$STATUS" != "RUNNING" ]; then
  echo "==> VM is not running. Starting it first..."
  gcloud compute instances start "$VM_NAME" --zone="$ZONE" --quiet
  sleep 10
fi

IP=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo "==> Removing old container and pulling latest image..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --command \
  'docker stop valheim-server 2>/dev/null || true && docker rm valheim-server 2>/dev/null || true'

# Re-run the startup script, which will see no container and create a fresh one
echo "==> Re-running startup script (fresh container + Steam download)..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --command \
  'sudo google_metadata_script_runner startup'

echo "==> Waiting for Valheim server to be ready..."

READY_TIMEOUT=600
POLL_INTERVAL=5
BOOT_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
elapsed=0
while [ $elapsed -lt $READY_TIMEOUT ]; do
  if gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --command \
    "docker logs --since '$BOOT_TS' valheim-server 2>&1 | grep -q 'Registering lobby'" 2>/dev/null; then
    echo ""
    echo "==> Update complete! Server is ready."
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
echo "==> Timed out waiting for readiness (server may still be updating)."
echo "    Connect in Valheim: $IP:2456"
echo "    Check logs: gcloud compute ssh $VM_NAME --zone=$ZONE -- 'docker logs -f valheim-server'"
