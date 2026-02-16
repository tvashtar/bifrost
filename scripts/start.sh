#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo "==> Starting $VM_NAME..."
gcloud compute instances start "$VM_NAME" --zone="$ZONE" --quiet

echo "==> Waiting for VM to get an IP..."
sleep 5

IP=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo ""
echo "==> Server is starting up!"
echo "    Connect in Valheim: $IP:2456"
echo ""
echo "    Note: Valheim takes 1-2 min to be ready after VM starts."
echo "    Check logs: gcloud compute ssh $VM_NAME --zone=$ZONE -- 'docker logs -f \$(docker ps -q)'"
