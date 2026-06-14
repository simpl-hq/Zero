#!/bin/bash

set -e

trap "rm apps/multiplatform/local.properties 2> /dev/null || true; rm local.properties 2> /dev/null || true; rm /tmp/zero.keychain" EXIT
echo "desktop.mac.signing.identity=Developer ID Application: Zero (5NN7GUYB6T)" >> apps/multiplatform/local.properties
echo "desktop.mac.signing.keychain=/tmp/zero.keychain" >> apps/multiplatform/local.properties
echo "desktop.mac.notarization.apple_id=$APPLE_ZERO_NOTARIZATION_APPLE_ID" >> apps/multiplatform/local.properties
echo "desktop.mac.notarization.password=$APPLE_ZERO_NOTARIZATION_PASSWORD" >> apps/multiplatform/local.properties
echo "desktop.mac.notarization.team_id=5NN7GUYB6T" >> apps/multiplatform/local.properties
echo "$APPLE_ZERO_SIGNING_KEYCHAIN" | base64 --decode -o /tmp/zero.keychain

security unlock-keychain -p "" /tmp/zero.keychain
security list-keychains -s `security list-keychains | xargs` /tmp/zero.keychain
scripts/desktop/build-lib-mac.sh
cd apps/multiplatform
if [ -n "${ASSETS_DIR:-}" ]; then
  set -- -Pzero.assets.dir="$ASSETS_DIR"
else
  set --
fi
./gradlew "$@" packageDmg
./gradlew "$@" notarizeDmg
