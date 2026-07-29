#!/bin/sh

set -e

langs=( en bg cs de es fi fr hu it ja nl pl ru th tr uk zh-Hans )

for lang in "${langs[@]}"; do
  echo "***"
  echo "***"
  echo "***"
  echo "*** Importing $lang"
  xcodebuild -importLocalizations \
            -project ./apps/ios/Zero.xcodeproj \
            -localizationPath ./apps/ios/Zero\ Localizations/$lang.xcloc \
            -skipPackageUpdates
  sleep 10
done
