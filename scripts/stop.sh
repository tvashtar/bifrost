#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

STATUS=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --format='get(status)' 2>/dev/null) || true

if [ "$STATUS" != "RUNNING" ]; then
  echo "==> $GAME_DISPLAY_NAME server is already stopped (${STATUS:-not found})."
  exit 0
fi

echo "==> Stopping $GAME_DISPLAY_NAME container gracefully (allowing world save)..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  "docker stop --time $GAME_STOP_TIMEOUT $GAME_CONTAINER_NAME 2>/dev/null || true"

echo "==> Stopping VM..."
gcloud compute instances stop "$VM_NAME" --zone="$ZONE" --quiet

echo ""
echo "==> Server stopped. Only disk storage is billed (~\$0.40/mo)."
echo "    Restart with: ./bifrost${GAME:+ --game=$GAME} start"
