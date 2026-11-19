#!/usr/bin/env bash

set -e

function readlink() {
  echo "$(cd "$(dirname "$1")"; pwd -P)"
}

OS=linux
ARCH="$(uname -m)"
DATABASE_BACKEND="${1:-sqlite}"
GHC_VERSION=9.6.3

if [ "$ARCH" == "aarch64" ]; then
    COMPOSE_ARCH=arm64
else
    COMPOSE_ARCH=x64
fi

root_dir="$(dirname "$(dirname "$(readlink "$0")")")"
cd $root_dir
BUILD_DIR=dist-newstyle/build/$ARCH-$OS/ghc-${GHC_VERSION}/zero-runtime-*

exports=( $(awk '/^foreign export ccall / { sym=$4; gsub(/"/, "", sym); if (sym != "zero_core_runtime_migrate_init_key" && sym != "zero_core_runtime_reopen_store") print sym }' src/Zero/Chat/Mobile.hs) )
for elem in "${exports[@]}"; do count=$(grep -R "$elem$" libzero.dll.def | wc -l); if [ $count -ne 1 ]; then echo Wrong exports in libzero.dll.def. Add \"$elem\" to that file; exit 1; fi ; done
for elem in "${exports[@]}"; do count=$(grep -R "\"$elem\"" flake.nix | wc -l); if [ $count -ne 2 ]; then echo Wrong exports in flake.nix. Add \"$elem\" in two places of the file; exit 1; fi ; done

REPO_ROOT="$(pwd)"
CABAL_LOCAL_BACKUP=""
if [ -f "$REPO_ROOT/cabal.project.local" ]; then
    CABAL_LOCAL_BACKUP="$(mktemp)"
    cp "$REPO_ROOT/cabal.project.local" "$CABAL_LOCAL_BACKUP"
fi
restore_cabal_local() {
    if [ -n "$CABAL_LOCAL_BACKUP" ] && [ -f "$CABAL_LOCAL_BACKUP" ]; then
        cp "$CABAL_LOCAL_BACKUP" "$REPO_ROOT/cabal.project.local"
        rm -f "$CABAL_LOCAL_BACKUP"
    else
        rm -f "$REPO_ROOT/cabal.project.local"
    fi
}
trap restore_cabal_local EXIT

cat <<'EOF' >> "$REPO_ROOT/cabal.project.local"

package zero-runtime
    ghc-options: -optl-Wl,-rpath,$ORIGIN -optl-Wl,-soname,libzero.so -flink-rts -threaded
EOF

if [[ "$DATABASE_BACKEND" == "postgres" ]]; then
    echo "Building with postgres backend..."
    cabal build lib:zero-runtime --constraint 'zeroq +client_library +client_postgres' --constraint 'zero-runtime +client_library +client_postgres'
else
    echo "Building with sqlite backend..."
    cabal build lib:zero-runtime --constraint 'zeroq +client_library' --constraint 'zero-runtime +client_library'
fi
cd $BUILD_DIR/build
mv libHSzero-runtime-*-inplace-ghc${GHC_VERSION}.so libzero.so 2> /dev/null || true

patchelf --replace-needed "libffi.so.7" "libffi.so.8" libzero.so

mkdir deps 2> /dev/null || true
ldd libzero.so | grep "ghc" | cut -d' ' -f 3 | xargs -I {} cp {} ./deps/
for dep in ./deps/*.so*; do
    [ -f "$dep" ] || continue
    chmod u+w "$dep"
    patchelf --set-rpath '$ORIGIN' "$dep" || true
done

cd -

rm -rf apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
rm -rf apps/multiplatform/desktop/build/cmake

mkdir -p apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
cp -r $BUILD_DIR/build/deps/* apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
cp $BUILD_DIR/build/libzero.so apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
scripts/desktop/prepare-vlc-linux.sh
bash scripts/desktop/prepare-tor.sh linux "$ARCH" "apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/tor"

links_dir=apps/multiplatform/build/links
mkdir -p $links_dir
cd $links_dir
ln -sfT ../../common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/ $OS-$COMPOSE_ARCH
