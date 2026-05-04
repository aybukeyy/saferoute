#!/usr/bin/env bash
# Pull the Gemma 4 weights from the Safe Route app's private storage on a
# connected Android device/emulator into a host-side cache directory, so a
# fresh APK install can later be restored without re-downloading from
# Hugging Face. Destination defaults to `~/.saferoute-models/` — override
# with SAFEROUTE_MODELS_DIR.
#
# Usage:
#   tools/backup-models.sh              # uses first connected device
#   tools/backup-models.sh -s emulator-5554
#
# Prereqs:
#   - Debug build of Safe Route on the device (release builds aren't run-as
#     accessible).
#   - Models already downloaded on the device (open the app once, complete
#     onboarding, wait for both downloads).

set -euo pipefail

DST_DIR="${SAFEROUTE_MODELS_DIR:-$HOME/.saferoute-models}"
PKG="com.saferoute.app"
ADB_BIN="${ADB:-$(command -v adb || echo /opt/homebrew/share/android-commandlinetools/platform-tools/adb)}"
SERIAL_ARGS=()

if [ "${1:-}" = "-s" ] && [ -n "${2:-}" ]; then
  SERIAL_ARGS=(-s "$2")
fi

if [ ! -x "$ADB_BIN" ]; then
  echo "adb not found. Set ADB env var or install platform-tools." >&2
  exit 1
fi

mkdir -p "$DST_DIR"
FILES=(gemma-4-e2b.litertlm gemma-4-e4b.litertlm)

echo "Backing up ${#FILES[@]} models from $PKG to $DST_DIR..."
for f in "${FILES[@]}"; do
  echo "  → $f"
  "$ADB_BIN" "${SERIAL_ARGS[@]}" exec-out "run-as $PKG cat files/$f" > "$DST_DIR/$f"
  size=$(stat -f%z "$DST_DIR/$f" 2>/dev/null || stat -c%s "$DST_DIR/$f")
  if [ "$size" -lt 1000000 ]; then
    echo "    FAIL — pulled file is only $size bytes (run-as failed?)" >&2
    rm -f "$DST_DIR/$f"
    exit 1
  fi
  echo "    ok ($((size / 1024 / 1024)) MB)"
done

echo "Done. Restore with: tools/restore-models.sh"
