#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo "==> Stopping $GAME_DISPLAY_NAME container gracefully (allowing world save)..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
  "docker stop --time $GAME_STOP_TIMEOUT $GAME_CONTAINER_NAME 2>/dev/null || true"

echo "==> Stopping VM..."
gcloud compute instances stop "$VM_NAME" --zone="$ZONE" --quiet

echo ""
echo "==> Server stopped. Only disk storage is billed (~\$0.40/mo)."
echo "    Restart with: ./bifrost${GAME:+ --game=$GAME} start"
