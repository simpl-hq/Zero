#!/bin/sh

set -e

PBXPROJ=./apps/ios/Zero.xcodeproj/project.pbxproj
LIB_DIR=./apps/ios/Libraries/ios

if [ ! -f "$PBXPROJ" ]; then
    echo "Error: $PBXPROJ not found. Run from repo root." >&2
    exit 1
fi
if [ ! -d "$LIB_DIR" ]; then
    echo "Error: $LIB_DIR not found. Run prepare.sh first." >&2
    exit 1
fi

NEW_PLAIN=
NEW_GHC=
for f in "$LIB_DIR"/libHSzero-runtime-*.a; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    case "$base" in
        *-ghc*) NEW_GHC=$base ;;
        *)      NEW_PLAIN=$base ;;
    esac
done
if [ -z "$NEW_PLAIN" ] || [ -z "$NEW_GHC" ]; then
    echo "Error: expected libHSzero-runtime-*.a and -ghc*.a in $LIB_DIR." >&2
    echo "Run prepare.sh first." >&2
    exit 1
fi

OLD_PLAIN=
OLD_GHC=
for ref in $(grep -hoE 'libHSzero-runtime-[^ "/]+\.a' "$PBXPROJ" | sort -u); do
    case "$ref" in
        *-ghc*) OLD_GHC=$ref ;;
        *)      OLD_PLAIN=$ref ;;
    esac
done
if [ -z "$OLD_PLAIN" ] || [ -z "$OLD_GHC" ]; then
    echo "Error: no libHSzero-runtime references found in $PBXPROJ." >&2
    exit 1
fi

if [ "$OLD_PLAIN" = "$NEW_PLAIN" ] && [ "$OLD_GHC" = "$NEW_GHC" ]; then
    echo "Already up to date: $NEW_PLAIN"
    exit 0
fi

OLD_PLAIN_LINES=$(grep -cF "$OLD_PLAIN" "$PBXPROJ" || true)
OLD_GHC_LINES=$(grep -cF "$OLD_GHC" "$PBXPROJ" || true)
if [ "$OLD_PLAIN_LINES" -ne 4 ] || [ "$OLD_GHC_LINES" -ne 4 ]; then
    echo "Error: expected 4 + 4 lines, found $OLD_PLAIN_LINES plain and $OLD_GHC_LINES ghc." >&2
    exit 1
fi

echo "Replacing in $PBXPROJ:"
echo "  $OLD_PLAIN -> $NEW_PLAIN"
echo "  $OLD_GHC -> $NEW_GHC"

escape_dots() { printf '%s' "$1" | sed 's/\./\\./g'; }
OLD_PLAIN_RE=$(escape_dots "$OLD_PLAIN")
OLD_GHC_RE=$(escape_dots "$OLD_GHC")

TMP=$(mktemp "$PBXPROJ.XXXXXX")
trap 'rm -f "$TMP"' EXIT
sed -e "s|$OLD_GHC_RE|$NEW_GHC|g" -e "s|$OLD_PLAIN_RE|$NEW_PLAIN|g" "$PBXPROJ" > "$TMP"
mv "$TMP" "$PBXPROJ"

NEW_PLAIN_LINES=$(grep -cF "$NEW_PLAIN" "$PBXPROJ" || true)
NEW_GHC_LINES=$(grep -cF "$NEW_GHC" "$PBXPROJ" || true)
if [ "$NEW_PLAIN_LINES" -ne 4 ] || [ "$NEW_GHC_LINES" -ne 4 ]; then
    echo "Error: post-replacement: $NEW_PLAIN_LINES plain + $NEW_GHC_LINES ghc (expected 4+4)." >&2
    exit 1
fi
echo "Updated 8 lines (4 plain + 4 ghc)."
