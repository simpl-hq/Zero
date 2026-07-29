#!/bin/sh

set -eu

if [ -n "${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-}" ]; then
  case " $SWIFT_ACTIVE_COMPILATION_CONDITIONS " in
    *" ZERO_ASSETS "*) ;;
    *) exit 0 ;;
  esac
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$SCRIPT_DIR/../../apps/ios/Shared/ZeroAssets.xcassets"

ASSETS_ROOT="${1:-${ZERO_ASSETS_DIR:-}}"
if [ -z "$ASSETS_ROOT" ]; then
  echo "warning: ZERO_ASSETS_DIR not set and no path argument provided" >&2
  exit 0
fi

SRC_DIR="$ASSETS_ROOT/ios/Assets.xcassets"

if [ ! -d "$SRC_DIR" ]; then
  echo "warning: source assets not found: $SRC_DIR (run resize.sh first)" >&2
  exit 0
fi

find "$IOS_DIR" -name "*.imageset" -type d -exec rm -rf {} + 2>/dev/null || true

for imageset in "$SRC_DIR"/*.imageset; do
  [ -d "$imageset" ] || continue
  cp -r "$imageset" "$IOS_DIR/"
  echo "Copied $(basename "$imageset")"
done

echo "Done. Assets copied to $IOS_DIR"
