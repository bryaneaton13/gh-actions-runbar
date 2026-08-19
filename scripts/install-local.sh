#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/RunBar.app"
DEST="$HOME/Applications"

if [[ ! -d "$APP" ]]; then
  echo "Run ./scripts/build-app.sh first." >&2
  exit 1
fi

mkdir -p "$DEST"
rm -rf "$DEST/RunBar.app"
cp -R "$APP" "$DEST/RunBar.app"

echo "Installed $DEST/RunBar.app"
echo "Open it with: open ~/Applications/RunBar.app"
