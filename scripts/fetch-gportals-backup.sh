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
REMOTE_DIR="${FTP_URL}/save/worlds_local"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TARBALL="$BACKUP_DIR/../${WORLD_NAME}-gportals-${TIMESTAMP}.tar.gz"

echo "==> Listing files from Gportals FTP..."

# Valheim 1.0+: the world is a directory of chunk files + _main.<N>.* metadata
WORLD_FILES=$(curl -s --list-only "${REMOTE_DIR}/${WORLD_NAME}/" | tr -d '\r' | grep -vE '^\.{1,2}$' || true)

if echo "$WORLD_FILES" | grep -qE '^_main\.[0-9]+\.fwl2$'; then
  echo "    Found world directory: ${WORLD_NAME}/ ($(echo "$WORLD_FILES" | wc -l | tr -d ' ') files)"

  # Start clean so files from an older download don't mix with this one
  rm -rf "${BACKUP_DIR:?}/${WORLD_NAME}"
  mkdir -p "$BACKUP_DIR/$WORLD_NAME"

  echo "==> Downloading world files..."
  while IFS= read -r f; do
    curl -s --fail -o "$BACKUP_DIR/$WORLD_NAME/$f" "${REMOTE_DIR}/${WORLD_NAME}/${f}"
  done <<< "$WORLD_FILES"

  echo "==> Creating backup tarball..."
  tar -czf "$TARBALL" -C "$BACKUP_DIR" "$WORLD_NAME"
  DOWNLOADED="$BACKUP_DIR/$WORLD_NAME/"
else
  # Legacy: <world>.db + <world>.fwl
  FILES=$(curl -s --list-only "${REMOTE_DIR}/" | tr -d '\r')
  DB_FILE=$(echo "$FILES" | grep -x "${WORLD_NAME}\.db" || true)
  FWL_FILE=$(echo "$FILES" | grep -x "${WORLD_NAME}\.fwl" || true)

  if [ -z "$DB_FILE" ] || [ -z "$FWL_FILE" ]; then
    echo "ERROR: No world found for: $WORLD_NAME"
    echo "    Looked for ${WORLD_NAME}/_main.<N>.fwl2 (Valheim 1.0+) and ${WORLD_NAME}.db + .fwl (legacy)"
    echo "Available files:"
    echo "$FILES"
    exit 1
  fi

  echo "    Found: $DB_FILE"
  echo "    Found: $FWL_FILE"

  echo "==> Downloading world files..."
  curl -s --fail -o "$BACKUP_DIR/$DB_FILE" "${REMOTE_DIR}/${DB_FILE}"
  curl -s --fail -o "$BACKUP_DIR/$FWL_FILE" "${REMOTE_DIR}/${FWL_FILE}"

  echo "==> Creating backup tarball..."
  tar -czf "$TARBALL" -C "$BACKUP_DIR" "$DB_FILE" "$FWL_FILE"
  DOWNLOADED="$BACKUP_DIR/$DB_FILE, $BACKUP_DIR/$FWL_FILE"
fi

TARBALL_REL="backups/$(basename "$TARBALL")"
echo ""
echo "==> Backup complete!"
echo "    Files: $DOWNLOADED"
echo "    Tarball: $TARBALL_REL"
echo ""
echo "    To restore: ./bifrost restore $TARBALL_REL"
echo ""
