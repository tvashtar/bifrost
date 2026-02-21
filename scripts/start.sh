#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Timing helper
START_TIME=$(date +%s)
step_start() { STEP_START=$(date +%s); }
step_end() {
  local elapsed=$(($(date +%s) - STEP_START))
  echo "    (took ${elapsed}s)"
}

POLL_INTERVAL=5

step_start
echo "==> Starting $VM_NAME..."
gcloud compute instances start "$VM_NAME" --zone="$ZONE" --quiet
step_end

step_start
echo "==> Waiting for VM to get an IP..."
sleep 5

IP=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo "    VM IP: $IP"
step_end

step_start
echo "==> Waiting for $GAME_DISPLAY_NAME server to be ready (this can take 2-8 min)..."

# Capture the current timestamp so we only match log lines from THIS boot,
# not stale lines from a previous run still in the container's log history.
BOOT_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

elapsed=0
while [ $elapsed -lt $GAME_READY_TIMEOUT ]; do
  # Check docker logs since this boot for the real ready signal
  if gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --command \
    "docker logs --since '$BOOT_TS' $GAME_CONTAINER_NAME 2>&1 | grep -q '$GAME_READY_SIGNAL'" 2>/dev/null; then
    step_end
    TOTAL_TIME=$(($(date +%s) - START_TIME))
    echo ""
    echo "==> Server is ready!"
    echo "    Total start time: ${TOTAL_TIME}s ($((TOTAL_TIME / 60))m $((TOTAL_TIME % 60))s)"
    echo "    Connect to $GAME_DISPLAY_NAME: $IP:$GAME_CONNECT_PORT"
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

TOTAL_TIME=$(($(date +%s) - START_TIME))
echo ""
echo "==> Timed out after ${GAME_READY_TIMEOUT}s waiting for server readiness."
echo "    Total time: ${TOTAL_TIME}s ($((TOTAL_TIME / 60))m $((TOTAL_TIME % 60))s)"
echo "    The server may still be starting."
echo "    Connect to $GAME_DISPLAY_NAME: $IP:$GAME_CONNECT_PORT"
echo "    Check logs: gcloud compute ssh $VM_NAME --zone=$ZONE -- 'docker logs -f $GAME_CONTAINER_NAME'"
