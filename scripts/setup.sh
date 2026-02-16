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

echo "==> Creating firewall rule for UDP 2456-2457..."
gcloud compute firewall-rules create "$FIREWALL_RULE" \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=udp:2456-2457 \
  --source-ranges=0.0.0.0/0 \
  --target-tags="$NETWORK_TAG" \
  2>/dev/null || echo "    (firewall rule already exists, skipping)"

echo "==> Creating persistent disk for world saves..."
gcloud compute disks create "$DISK_NAME" \
  --zone="$ZONE" \
  --size="${DISK_SIZE}GB" \
  --type=pd-standard \
  2>/dev/null || echo "    (disk already exists, skipping)"

echo "==> Creating VM with Container-Optimized OS..."
gcloud compute instances create-with-container "$VM_NAME" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --image-family=cos-stable \
  --image-project=cos-cloud \
  --boot-disk-size=30GB \
  --tags="$NETWORK_TAG" \
  --disk="name=$DISK_NAME,device-name=valserver-data,mode=rw,auto-delete=no" \
  --container-image="$VALHEIM_IMAGE" \
  --container-env="SERVER_NAME=$SERVER_NAME,SERVER_PASS=$SERVER_PASS,WORLD_NAME=$WORLD_NAME,SERVER_PUBLIC=$SERVER_PUBLIC" \
  --container-mount-disk="mount-path=/config,name=valserver-data" \
  --container-restart-policy=always \
  --metadata=google-logging-enabled=true

IP=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo ""
echo "==> Setup complete!"
echo "    Server is booting (first start takes 2-5 min to download Valheim)."
echo "    Connect in Valheim: $IP:2456"
echo "    Password: (the one you set)"
echo ""
echo "    Check logs:  gcloud compute ssh $VM_NAME --zone=$ZONE -- 'docker logs -f \$(docker ps -q)'"
echo "    Stop server: ./scripts/stop.sh"
