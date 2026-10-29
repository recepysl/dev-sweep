#!/usr/bin/env bash
set -euo pipefail

APP="/Applications/DevSweep.app"
BUNDLE_ID="io.github.recepysl.dev-sweep"

pkill -f "DevSweep.app/Contents/MacOS/DevSweep" 2>/dev/null || true
rm -rf "$APP"
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
rm -rf "$HOME/Library/Application Support/$BUNDLE_ID"

echo "✓ Removed DevSweep, its preferences and its scan cache."
echo "  If it still appears under System Settings → General → Login Items, remove it there."
