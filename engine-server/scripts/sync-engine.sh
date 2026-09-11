#!/usr/bin/env bash
# Re-pulls a fresh copy of the DOM-free rules engine (engine/*.js) from the 2D
# Campaign-OS checkout this project was forked alongside. There is exactly ONE
# real source of truth for 5e rules logic -- the 2D repo's engine/ folder -- and
# this 3D project never edits its own copy in place; it only ever overwrites it
# wholesale from there, the same "manual sync, audited by hand" convention
# Campaign-OS's own CLAUDE.md already documents for its duplicated lookup lists
# (MONSTER_LIST/CONDITION_LIST/etc. between the browser engine and dm-bridge/watch.js).
#
# Usage: scripts/sync-engine.sh [path-to-Campaign-OS-checkout]
# Defaults to ../../Campaign-OS (i.e. a sibling checkout next to this project).

set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="${1:-../../Campaign-OS}"
DEST="engine"

if [ ! -d "$SOURCE/engine" ]; then
  echo "Could not find $SOURCE/engine -- pass the Campaign-OS checkout path explicitly." >&2
  exit 1
fi

for f in encounter.js dmBridge.js campaign.js characterCreator.js; do
  if [ -f "$DEST/$f" ] && ! diff -q "$SOURCE/engine/$f" "$DEST/$f" > /dev/null 2>&1; then
    echo "CHANGED: $f (review before committing -- the 3D client may rely on behavior that just shifted)"
  fi
  cp "$SOURCE/engine/$f" "$DEST/$f"
done

echo "Synced engine/*.js from $SOURCE/engine."
