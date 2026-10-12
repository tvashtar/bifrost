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
  echo "Usage: ./bifrost export-world [path/to/worlds]"
  echo ""
  echo "Checked:"
  echo "  $STEAM_WORLDS_DIR"
  echo "  $LOCAL_WORLDS_DIR"
  exit 1
fi

# List available worlds:
#   Valheim 1.0+: <world>/_main.<N>.fwl2 (a directory per world)
#   Legacy:       <world>.fwl
echo "==> Available worlds in: $WORLDS_DIR"
WORLDS=()
add_world() {
  [[ "$1" == *_backup_* ]] && return 0
  [[ " ${WORLDS[*]-} " == *" $1 "* ]] && return 0
  WORLDS+=("$1")
  echo "    - $1"
}
while IFS= read -r fwl2; do
  add_world "$(basename "$(dirname "$fwl2")")"
done < <(find "$WORLDS_DIR" -mindepth 2 -maxdepth 2 -name "_main.*.fwl2" 2>/dev/null)
while IFS= read -r fwl; do
  add_world "$(basename "$fwl" .fwl)"
done < <(find "$WORLDS_DIR" -maxdepth 1 -name "*.fwl" 2>/dev/null)

if [ ${#WORLDS[@]} -eq 0 ]; then
  echo "    No worlds found (.fwl2 or .fwl files)"
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

# Package into the same format as backup.sh (tar of worlds_local contents,
# extracted by restore.sh into /config/worlds_local/)
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/valheim-$WORLD-$TIMESTAMP.tar.gz"

if [ -d "$WORLDS_DIR/$WORLD" ]; then
  # Valheim 1.0+: the whole world directory (the server loads the newest
  # generation that has a matching _main.<N>.ok)
  tar czf "$BACKUP_FILE" -C "$WORLDS_DIR" "$WORLD"
else
  # Legacy: <world>.fwl + <world>.db (+ .old copies if present)
  FILES=()
  for f in "$WORLD.fwl" "$WORLD.db" "$WORLD.fwl.old" "$WORLD.db.old"; do
    [ -f "$WORLDS_DIR/$f" ] && FILES+=("$f")
  done
  tar czf "$BACKUP_FILE" -C "$WORLDS_DIR" "${FILES[@]}"
fi

echo ""
echo "==> Exported to: $BACKUP_FILE"
ls -lh "$BACKUP_FILE"
echo ""
echo "    Restore to server with: ./bifrost restore $BACKUP_FILE"
