#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
BACKUP_DIR="$REPO_ROOT/backups/gportals"

# Load FTP credentials from .env
ENV_FILE="$REPO_ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env file not found at $ENV_FILE"
  echo "Create it with: FTP_URL=\"ftp://username:password@host:port\""
  exit 1
fi

source "$ENV_FILE"

if [ -z "${FTP_URL:-}" ]; then
  echo "ERROR: FTP_URL not set in .env"
  exit 1
fi

# Get world name argument (optional)
WORLD_NAME="${1:-}"
if [ -z "$WORLD_NAME" ]; then
  echo "Usage: $0 <world-name>"
  echo "Example: $0 Finnland"
  exit 1
fi

echo "==> Fetching latest backup for world: $WORLD_NAME"
echo "==> Listing files from Gportals FTP..."

# List all files in save/worlds_local/
FILES=$(curl -s "${FTP_URL}/save/worlds_local/" | grep -E "${WORLD_NAME}\.(db|fwl)" | awk '{print $9}')

if [ -z "$FILES" ]; then
  echo "ERROR: No files found for world: $WORLD_NAME"
  exit 1
fi

# Find the most recent .db and .fwl files (not backups with timestamps)
DB_FILE=$(echo "$FILES" | grep "^${WORLD_NAME}\.db$" || true)
FWL_FILE=$(echo "$FILES" | grep "^${WORLD_NAME}\.fwl$" || true)

if [ -z "$DB_FILE" ] || [ -z "$FWL_FILE" ]; then
  echo "ERROR: Could not find both ${WORLD_NAME}.db and ${WORLD_NAME}.fwl"
  echo "Available files:"
  echo "$FILES"
  exit 1
fi

echo "    Found: $DB_FILE"
echo "    Found: $FWL_FILE"

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo "==> Downloading world files..."
cd "$BACKUP_DIR"

curl -s -O "${FTP_URL}/save/worlds_local/${DB_FILE}"
curl -s -O "${FTP_URL}/save/worlds_local/${FWL_FILE}"

echo "==> Creating backup tarball..."
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TARBALL="../${WORLD_NAME}-gportals-${TIMESTAMP}.tar.gz"
tar -czf "$TARBALL" "$DB_FILE" "$FWL_FILE"

echo ""
echo "==> Backup complete!"
echo "    Files: $BACKUP_DIR/$DB_FILE"
echo "           $BACKUP_DIR/$FWL_FILE"
echo "    Tarball: ${TARBALL#../}"
echo ""
echo "    To restore: ./val restore ${TARBALL#../}"
echo ""
