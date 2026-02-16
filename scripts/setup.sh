#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

if [ -z "$SERVER_PASS" ]; then
  echo "ERROR: SERVER_PASS must be set (min 5 characters)."
  echo "Usage: SERVER_PASS='yourpass' ./scripts/setup.sh"
  exit 1
fi

if [ ${#SERVER_PASS} -lt 5 ]; then
  echo "ERROR: SERVER_PASS must be at least 5 characters."
  exit 1
fi

echo "==> Setting project to $PROJECT"
gcloud config set project "$PROJECT" --quiet

echo "==> Enabling Compute Engine API (if needed)..."
gcloud services enable compute.googleapis.com --quiet

echo "==> Creating firewall rule for UDP 2456-2457..."
gcloud compute firewall-rules create "$FIREWALL_RULE" \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=udp:2456-2458 \
  --source-ranges=0.0.0.0/0 \
  --target-tags="$NETWORK_TAG" \
  2>/dev/null || echo "    (firewall rule already exists, skipping)"

echo "==> Creating persistent disk for world saves..."
gcloud compute disks create "$DISK_NAME" \
  --zone="$ZONE" \
  --size="${DISK_SIZE}GB" \
  --type=pd-standard \
  2>/dev/null || echo "    (disk already exists, skipping)"

# Write the startup script to a temp file for --metadata-from-file.
# COS comes with Docker preinstalled. This runs on every boot:
# formats the data disk on first use, mounts it, and starts the container.
STARTUP_FILE=$(mktemp)
trap 'rm -f "$STARTUP_FILE"' EXIT

cat > "$STARTUP_FILE" <<EOF
#!/bin/bash
set -e

DATA_DEV="/dev/disk/by-id/google-valserver-data"
DATA_MNT="/var/valheim"

# Format the data disk if it has no filesystem
if ! blkid "\$DATA_DEV" &>/dev/null; then
  echo "Formatting data disk..."
  mkfs.ext4 -m 0 -F -E lazy_itable_init=0 "\$DATA_DEV"
fi

# Mount the data disk
mkdir -p "\$DATA_MNT"
mount -o discard,defaults "\$DATA_DEV" "\$DATA_MNT" || true

# Pull and run the Valheim server container
docker pull $VALHEIM_IMAGE

# Stop any existing container
docker rm -f valheim-server 2>/dev/null || true

docker run -d \
  --name valheim-server \
  --restart unless-stopped \
  --cap-add SYS_NICE \
  --stop-timeout 30 \
  -p 2456-2458:2456-2458/udp \
  -e SERVER_NAME="$SERVER_NAME" \
  -e SERVER_PASS="$SERVER_PASS" \
  -e WORLD_NAME="$WORLD_NAME" \
  -e SERVER_PUBLIC="$SERVER_PUBLIC" \
  -e BACKUPS_CRON="*/15 * * * *" \
  -v "\$DATA_MNT:/config" \
  $VALHEIM_IMAGE
EOF

echo "==> Creating VM with Container-Optimized OS..."
gcloud compute instances create "$VM_NAME" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --image-family=cos-stable \
  --image-project=cos-cloud \
  --boot-disk-size=30GB \
  --tags="$NETWORK_TAG" \
  --disk="name=$DISK_NAME,device-name=valserver-data,mode=rw,auto-delete=no" \
  --metadata-from-file=startup-script="$STARTUP_FILE" \
  --scopes=default

IP=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo ""
echo "==> Setup complete! VM IP: $IP"
echo "    First boot downloads ~1.9GB from Steam — this takes 5-8 min."
echo "==> Waiting for Valheim server to be ready..."

READY_TIMEOUT=600  # 10 minutes
POLL_INTERVAL=10
elapsed=0
while [ $elapsed -lt $READY_TIMEOUT ]; do
  if gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --command \
    'docker logs valheim-server 2>&1 | grep -q "Registering lobby"' 2>/dev/null; then
    echo ""
    echo "==> Server is ready!"
    echo "    Connect in Valheim: $IP:2456"
    echo "    Password: (the one you set)"
    echo ""
    echo "    Stop server: ./scripts/stop.sh"
    exit 0
  fi

  sleep $POLL_INTERVAL
  elapsed=$((elapsed + POLL_INTERVAL))
  if (( elapsed % 30 == 0 )); then
    echo "    ... still waiting (${elapsed}s elapsed)"
  fi
done

echo ""
echo "==> Timed out waiting for readiness (server may still be starting)."
echo "    Connect in Valheim: $IP:2456"
echo "    Check logs: gcloud compute ssh $VM_NAME --zone=$ZONE -- 'docker logs -f valheim-server'"
echo "    Stop server: ./scripts/stop.sh"
