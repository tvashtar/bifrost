#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

READY_TIMEOUT=600  # 10 minutes (first boot downloads ~1.9GB from Steam)
POLL_INTERVAL=5

echo "==> Starting $VM_NAME..."
gcloud compute instances start "$VM_NAME" --zone="$ZONE" --quiet

echo "==> Waiting for VM to get an IP..."
sleep 5

IP=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo "    VM IP: $IP"
echo "==> Waiting for Valheim server to be ready (this can take 2-8 min)..."

elapsed=0
while [ $elapsed -lt $READY_TIMEOUT ]; do
  # Check docker logs for the real ready signal
  if gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --command \
    'docker logs valheim-server 2>&1 | grep -q "Registering lobby"' 2>/dev/null; then
    echo ""
    echo "==> Server is ready!"
    echo "    Connect in Valheim: $IP:2456"
    echo ""
    exit 0
  fi

  sleep $POLL_INTERVAL
  elapsed=$((elapsed + POLL_INTERVAL))
  # Print a dot every 30 seconds so the user knows it's alive
  if (( elapsed % 30 == 0 )); then
    echo "    ... still waiting (${elapsed}s elapsed)"
  fi
done

echo ""
echo "==> Timed out after ${READY_TIMEOUT}s waiting for server readiness."
echo "    The server may still be starting (first boot downloads ~1.9GB)."
echo "    Connect in Valheim: $IP:2456"
echo "    Check logs: gcloud compute ssh $VM_NAME --zone=$ZONE -- 'docker logs -f valheim-server'"
