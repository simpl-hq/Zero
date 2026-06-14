#!/usr/bin/env sh

[ -n "$1" ] || exit 1
set -eu

tmp=$(mktemp -d -t)
libsim=$(cat "$1" | grep libzero)
libsup=$(cat "$1" | grep libsupport)
commit="${2:-nix-android}"

git clone https://github.com/simpl-hq/zero "$tmp/zero-runtime"

git -C "$tmp/zero-runtime" checkout "$commit"

mkdir -p "$tmp/zero-runtime/apps/multiplatform/common/src/commonMain/cpp/android/libs/arm64-v8a"

curl -sSf "$libsim" -o "$tmp/libzero.zip"
unzip -o "$tmp/libzero.zip" -d "$tmp/zero-runtime/apps/multiplatform/common/src/commonMain/cpp/android/libs/arm64-v8a"

curl -sSf "$libsup" -o "$tmp/libsupport.zip"
unzip -o "$tmp/libsupport.zip" -d "$tmp/zero-runtime/apps/multiplatform/common/src/commonMain/cpp/android/libs/arm64-v8a"

sed -i.bak 's/include(.*/include("arm64-v8a")/' "$tmp/zero-runtime/apps/multiplatform/android/build.gradle.kts"

gradle -p "$tmp/zero-runtime/apps/multiplatform/" -Pzero.assets.dir=../../assets clean :android:assembleFossRelease
cp "$tmp/zero-runtime/apps/multiplatform/android/build/outputs/apk/foss/release/android-foss-arm64-v8a-release-unsigned.apk" "$PWD/zero-runtime.apk"
