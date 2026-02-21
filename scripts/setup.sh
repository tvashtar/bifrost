#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Timing helper
SETUP_START=$(date +%s)
step_start() { STEP_START=$(date +%s); }
step_end() {
  local elapsed=$(($(date +%s) - STEP_START))
  echo "    (took ${elapsed}s)"
}

# Parse flags
RESTORE_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --size=small)  MACHINE_TYPE="e2-small";  shift ;;
    --size=medium) MACHINE_TYPE="e2-medium"; shift ;;
    --size=*)
      echo "ERROR: Unknown size '${1#--size=}'. Use --size=small or --size=medium."
      exit 1
      ;;
    --restore=*)
      RESTORE_FILE="${1#--restore=}"
      if [ ! -f "$RESTORE_FILE" ]; then
        echo "ERROR: Backup file not found: $RESTORE_FILE"
        exit 1
      fi
      shift
      ;;
    *)
      echo "Usage: ./val [--game=GAME] setup [--size=small|medium] [--restore=path/to/backup.tar.gz]"
      exit 1
      ;;
  esac
done

# If restoring, detect world name from backup (Valheim-specific: .fwl files)
if [ -n "$RESTORE_FILE" ]; then
  if [ "$GAME_ID" = "valheim" ]; then
    DETECTED_WORLD=$(tar tzf "$RESTORE_FILE" | grep -E '\.fwl$' | grep -v '_backup_' | head -1 | sed 's|.*/||; s|\.fwl$||')
    if [ -z "$DETECTED_WORLD" ]; then
      DETECTED_WORLD=$(tar tzf "$RESTORE_FILE" | grep -E '\.fwl$' | head -1 | sed 's|.*/||; s|\.fwl$||')
    fi
    if [ -n "$DETECTED_WORLD" ]; then
      echo "==> Detected world name from backup: $DETECTED_WORLD"
      WORLD_NAME="$DETECTED_WORLD"
    fi
  fi
  echo "==> Will restore from: $RESTORE_FILE (skips world generation)"
fi

echo "    Game: $GAME_DISPLAY_NAME"
echo "    Machine type: $MACHINE_TYPE"

# Game-specific validation (password checks, minimum VM size, etc.)
game_validate_config

echo "==> Setting project to $PROJECT"
gcloud config set project "$PROJECT" --quiet

step_start
echo "==> Enabling Compute Engine API (if needed)..."
gcloud services enable compute.googleapis.com --quiet
step_end

step_start
echo "==> Creating firewall rule for $GAME_DISPLAY_NAME ports..."
gcloud compute firewall-rules create "$FIREWALL_RULE" \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules="$GAME_PORTS_FIREWALL" \
  --source-ranges=0.0.0.0/0 \
  --target-tags="$NETWORK_TAG" \
  2>/dev/null || echo "    (firewall rule already exists, skipping)"
step_end

step_start
echo "==> Creating persistent disk for world saves..."
gcloud compute disks create "$DISK_NAME" \
  --zone="$ZONE" \
  --size="${DISK_SIZE}GB" \
  --type=pd-standard \
  2>/dev/null || echo "    (disk already exists, skipping)"
step_end

# Generate the startup script
STARTUP_FILE=$(mktemp)
trap 'rm -f "$STARTUP_FILE"' EXIT
generate_startup_script "$STARTUP_FILE"

step_start
echo "==> Creating VM with Container-Optimized OS..."
gcloud compute instances create "$VM_NAME" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --image-family=cos-stable \
  --image-project=cos-cloud \
  --boot-disk-size=10GB \
  --tags="$NETWORK_TAG" \
  --disk="name=$DISK_NAME,device-name=$DISK_NAME,mode=rw,auto-delete=no" \
  --metadata-from-file=startup-script="$STARTUP_FILE" \
  --scopes=default
step_end

IP=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo ""
echo "==> Setup complete! VM IP: $IP"

# If restoring, upload backup before container finishes starting
if [ -n "$RESTORE_FILE" ]; then
  step_start
  echo "==> Uploading world backup to server..."
  # Wait for SSH and data disk mount to be available
  for i in $(seq 1 24); do
    if gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
      "mountpoint -q $GAME_DATA_MOUNT" 2>/dev/null; then
      break
    fi
    sleep 5
  done
  gcloud compute scp "$RESTORE_FILE" "$VM_NAME:/tmp/${GAME_ID}-restore.tar.gz" \
    --zone="$ZONE" --quiet
  gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet -- \
    "sudo mkdir -p $GAME_DATA_MOUNT/$GAME_WORLD_SUBDIR && sudo tar xzf /tmp/${GAME_ID}-restore.tar.gz -C $GAME_DATA_MOUNT/$GAME_WORLD_SUBDIR/ && rm -f /tmp/${GAME_ID}-restore.tar.gz"
  echo "    World files uploaded."
  step_end
fi

echo "    $GAME_BOOT_MESSAGE"
step_start
echo "==> Waiting for $GAME_DISPLAY_NAME server to be ready..."

POLL_INTERVAL=10
BOOT_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
elapsed=0
while [ $elapsed -lt $GAME_READY_TIMEOUT ]; do
  if gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --command \
    "docker logs --since '$BOOT_TS' $GAME_CONTAINER_NAME 2>&1 | grep -q '$GAME_READY_SIGNAL'" 2>/dev/null; then
    step_end
    TOTAL_TIME=$(($(date +%s) - SETUP_START))
    echo ""
    echo "==> Server is ready!"
    echo "    Total setup time: ${TOTAL_TIME}s ($((TOTAL_TIME / 60))m $((TOTAL_TIME % 60))s)"
    echo "    Connect to $GAME_DISPLAY_NAME: $IP:$GAME_CONNECT_PORT"
    echo "    Password: (the one you set)"
    echo ""
    echo "    Stop server: ./val${GAME:+ --game=$GAME} stop"
    exit 0
  fi

  sleep $POLL_INTERVAL
  elapsed=$((elapsed + POLL_INTERVAL))
  if (( elapsed % 30 == 0 )); then
    echo "    ... still waiting (${elapsed}s elapsed)"
  fi
done

TOTAL_TIME=$(($(date +%s) - SETUP_START))
echo ""
echo "==> Timed out waiting for readiness (server may still be starting)."
echo "    Total time: ${TOTAL_TIME}s ($((TOTAL_TIME / 60))m $((TOTAL_TIME % 60))s)"
echo "    Connect to $GAME_DISPLAY_NAME: $IP:$GAME_CONNECT_PORT"
echo "    Check logs: gcloud compute ssh $VM_NAME --zone=$ZONE -- 'docker logs -f $GAME_CONTAINER_NAME'"
echo "    Stop server: ./val${GAME:+ --game=$GAME} stop"
