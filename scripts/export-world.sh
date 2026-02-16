#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/../backups}"

# macOS Valheim world save paths (Steam cloud + local)
STEAM_WORLDS_DIR="$HOME/Library/Application Support/Steam/userdata/54792297/892970/remote/worlds"
LOCAL_WORLDS_DIR="$HOME/Library/Application Support/IronGate/Valheim/worlds_local"

if [ $# -ge 1 ]; then
  WORLDS_DIR="$1"
elif [ -d "$STEAM_WORLDS_DIR" ]; then
  WORLDS_DIR="$STEAM_WORLDS_DIR"
elif [ -d "$LOCAL_WORLDS_DIR" ]; then
  WORLDS_DIR="$LOCAL_WORLDS_DIR"
else
  echo "ERROR: No Valheim worlds directory found."
  echo ""
  echo "Usage: ./val export-world [path/to/worlds]"
  echo ""
  echo "Checked:"
  echo "  $STEAM_WORLDS_DIR"
  echo "  $LOCAL_WORLDS_DIR"
  exit 1
fi

# List available worlds (.fwl files define a world)
echo "==> Available worlds in: $WORLDS_DIR"
WORLDS=()
while IFS= read -r fwl; do
  name=$(basename "$fwl" .fwl)
  WORLDS+=("$name")
  echo "    - $name"
done < <(find "$WORLDS_DIR" -name "*.fwl" -maxdepth 1 2>/dev/null)

if [ ${#WORLDS[@]} -eq 0 ]; then
  echo "    No worlds found (.fwl files)"
  exit 1
fi

# Pick world
if [ ${#WORLDS[@]} -eq 1 ]; then
  WORLD="${WORLDS[0]}"
  echo "==> Using: $WORLD"
else
  echo ""
  read -r -p "Which world? " WORLD
  if [[ ! " ${WORLDS[*]} " =~ " ${WORLD} " ]]; then
    echo "ERROR: World '$WORLD' not found."
    exit 1
  fi
fi

# Package into the same format as backup.sh (tar of /config structure)
# The server expects worlds in /config/worlds_local/
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/valheim-backup-$TIMESTAMP.tar.gz"

# Create a temp dir with the expected directory structure
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/worlds_local"
cp "$WORLDS_DIR/$WORLD".fwl "$TMPDIR/worlds_local/"
cp "$WORLDS_DIR/$WORLD".db "$TMPDIR/worlds_local/" 2>/dev/null || true
cp "$WORLDS_DIR/$WORLD".db.old "$TMPDIR/worlds_local/" 2>/dev/null || true
cp "$WORLDS_DIR/$WORLD".fwl.old "$TMPDIR/worlds_local/" 2>/dev/null || true

tar czf "$BACKUP_FILE" -C "$TMPDIR" .

echo ""
echo "==> Exported to: $BACKUP_FILE"
ls -lh "$BACKUP_FILE"
echo ""
echo "    Restore to server with: ./val restore $BACKUP_FILE"
