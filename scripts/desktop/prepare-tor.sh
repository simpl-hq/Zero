#!/usr/bin/env bash
set -euo pipefail

# Downloads and SHA-256-verifies the official Tor Project Expert Bundle (16.0.1)
# and copies the tor binary + required shared libraries into the desktop app's
# native resource directory so Tor is bundled on Windows, macOS, and Linux.
#
# Usage: prepare-tor.sh <os: windows|linux|macos> <arch: x86_64|aarch64> <dest_dir>

OS_ARG="${1:-}"
ARCH_ARG="${2:-}"
DEST_DIR="${3:-}"

if [ -z "$OS_ARG" ] || [ -z "$ARCH_ARG" ] || [ -z "$DEST_DIR" ]; then
  echo "Usage: $0 <windows|linux|macos> <x86_64|aarch64> <dest_dir>" >&2
  exit 1
fi

TOR_VERSION="16.0.1"
KEY="${OS_ARG}-${ARCH_ARG}"

case "$KEY" in
  windows-x86_64)
    EXPECTED_SHA256="9eed3c3ff1fe43df034ce360196c9ec95472560d77ff55614d0cd5120edea27b"
    ;;
  linux-x86_64)
    EXPECTED_SHA256="7039cb16060ab22e669852e55774d894b55f25ea8bd0ab7194d3478429a58725"
    ;;
  linux-aarch64)
    EXPECTED_SHA256="67040520d44c87ccaaf5aa7df0dc1ff122eb938dbb600ae7722e8b6b75282a4b"
    ;;
  macos-x86_64)
    EXPECTED_SHA256="15464d99adc3bb4de1308260d79878336b04a1ac1aeff83e10f192de7d235946"
    ;;
  macos-aarch64)
    EXPECTED_SHA256="0b7d022017c31e3f972d06465bcd7ac50feb66ac825547419a934914fe4bb156"
    ;;
  *)
    echo "[zero] No Tor Expert Bundle mapping for $KEY; skipping." >&2
    exit 0
    ;;
esac

ARCHIVE="tor-expert-bundle-${KEY}-${TOR_VERSION}.tar.gz"
URL="https://dist.torproject.org/torbrowser/${TOR_VERSION}/${ARCHIVE}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[zero] Downloading Tor Expert Bundle ${TOR_VERSION} for ${KEY}..."
curl --fail --location --tlsv1.2 --retry 3 --retry-delay 2 "$URL" -o "${TMP_DIR}/${ARCHIVE}"

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA256="$(sha256sum "${TMP_DIR}/${ARCHIVE}" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  ACTUAL_SHA256="$(shasum -a 256 "${TMP_DIR}/${ARCHIVE}" | awk '{print $1}')"
else
  ACTUAL_SHA256="$(openssl sha256 "${TMP_DIR}/${ARCHIVE}" | awk '{print $NF}')"
fi

if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "[zero] SHA-256 mismatch for ${ARCHIVE}!" >&2
  echo "  expected: $EXPECTED_SHA256" >&2
  echo "  actual:   $ACTUAL_SHA256" >&2
  exit 1
fi
echo "[zero] Verified ${ARCHIVE} SHA-256: ${ACTUAL_SHA256}"

tar -xzf "${TMP_DIR}/${ARCHIVE}" -C "$TMP_DIR" tor/

rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"

if [ "$OS_ARG" = "windows" ]; then
  cp "${TMP_DIR}/tor/tor.exe" "$DEST_DIR/"
else
  cp "${TMP_DIR}/tor/tor" "$DEST_DIR/"
  chmod +x "${DEST_DIR}/tor"
  for lib in "${TMP_DIR}"/tor/*.so* "${TMP_DIR}"/tor/*.dylib; do
    [ -e "$lib" ] || continue
    cp -P "$lib" "$DEST_DIR/"
  done
  if [ "$OS_ARG" = "linux" ] && command -v strip >/dev/null 2>&1; then
    strip --strip-unneeded "${DEST_DIR}/tor" "${DEST_DIR}"/*.so* 2>/dev/null || true
  fi
fi

echo "[zero] Bundled Tor into ${DEST_DIR}:"
ls -lh "$DEST_DIR"
