#!/usr/bin/env bash
# Push the cached Gemma 4 weights into the Safe Route app's private storage on
# the connected Android device/emulator, so a fresh install doesn't trigger
# the multi-GB download from Hugging Face. Source dir is `~/.saferoute-models/`
# by default — override with SAFEROUTE_MODELS_DIR.
#
# Usage:
#   tools/restore-models.sh              # uses first connected device
#   tools/restore-models.sh -s emulator-5554
#
# Prereqs:
#   - The Safe Route app must already be installed (run `flutter run` once
#     so the app's private storage exists).
#   - Debug build (release builds aren't run-as accessible).

set -euo pipefail

SRC_DIR="${SAFEROUTE_MODELS_DIR:-$HOME/.saferoute-models}"
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

if [ ! -d "$SRC_DIR" ]; then
  echo "Source dir not found: $SRC_DIR" >&2
  exit 1
fi

FILES=(gemma-4-e2b.litertlm gemma-4-e4b.litertlm)

for f in "${FILES[@]}"; do
  local_path="$SRC_DIR/$f"
  if [ ! -f "$local_path" ]; then
    echo "Missing $local_path — run pull first." >&2
    exit 1
  fi
done

echo "Restoring ${#FILES[@]} models to $PKG via adb..."
for f in "${FILES[@]}"; do
  local_path="$SRC_DIR/$f"
  size=$(stat -f%z "$local_path" 2>/dev/null || stat -c%s "$local_path")
  echo "  → $f ($((size / 1024 / 1024)) MB)"

  # Stream the file directly into the app's private storage via stdin →
  # run-as. Avoids /data/local/tmp (~256 MB on most emulators) entirely.
  # `dd` reads from stdin, `bs=1M` for throughput.
  "$ADB_BIN" "${SERIAL_ARGS[@]}" shell "run-as $PKG sh -c 'cat > files/$f'" \
    < "$local_path"

  echo "    ok"
done

echo "Done. Verify with:"
echo "  $ADB_BIN ${SERIAL_ARGS[*]} shell \"run-as $PKG ls -la files/\""
