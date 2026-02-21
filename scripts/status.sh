#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Check if VM exists
if ! gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --format='get(status)' 2>/dev/null; then
  echo "{\"game\":\"$GAME_ID\",\"display_name\":\"$GAME_DISPLAY_NAME\",\"status\":\"not_setup\",\"ip\":\"\",\"port\":\"$GAME_CONNECT_PORT\"}"
  exit 0
fi

STATUS=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --format='get(status)')

if [ "$STATUS" = "RUNNING" ]; then
  IP=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
  echo "{\"game\":\"$GAME_ID\",\"display_name\":\"$GAME_DISPLAY_NAME\",\"status\":\"running\",\"ip\":\"$IP\",\"port\":\"$GAME_CONNECT_PORT\"}"
else
  echo "{\"game\":\"$GAME_ID\",\"display_name\":\"$GAME_DISPLAY_NAME\",\"status\":\"stopped\",\"ip\":\"\",\"port\":\"$GAME_CONNECT_PORT\"}"
fi
