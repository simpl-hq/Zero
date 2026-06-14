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

exports=( $(sed 's/foreign export ccall "zero_core_runtime_migrate_init_key"//' src/Zero/Chat/Mobile.hs | sed 's/foreign export ccall "zero_core_runtime_reopen_store"//' |grep "foreign export ccall" | cut -d '"' -f2) )
for elem in "${exports[@]}"; do count=$(grep -R "$elem$" libzero.dll.def | wc -l); if [ $count -ne 1 ]; then echo Wrong exports in libzero.dll.def. Add \"$elem\" to that file; exit 1; fi ; done
for elem in "${exports[@]}"; do count=$(grep -R "\"$elem\"" flake.nix | wc -l); if [ $count -ne 2 ]; then echo Wrong exports in flake.nix. Add \"$elem\" in two places of the file; exit 1; fi ; done

if [[ "$DATABASE_BACKEND" == "postgres" ]]; then
    echo "Building with postgres backend..."
    cabal build lib:zero-runtime --ghc-options='-optl-Wl,-rpath,$ORIGIN -optl-Wl,-soname,libzero.so -flink-rts -threaded' --constraint 'zeroq +client_library +client_postgres' --constraint 'zero-runtime +client_library +client_postgres'
else
    echo "Building with sqlite backend..."
    cabal build lib:zero-runtime --ghc-options='-optl-Wl,-rpath,$ORIGIN -optl-Wl,-soname,libzero.so -flink-rts -threaded' --constraint 'zeroq +client_library' --constraint 'zero-runtime +client_library'
fi
cd $BUILD_DIR/build
mv libHSzero-runtime-*-inplace-ghc${GHC_VERSION}.so libzero.so 2> /dev/null || true

patchelf --replace-needed "libffi.so.7" "libffi.so.8" libzero.so

mkdir deps 2> /dev/null || true
ldd libzero.so | grep "ghc" | cut -d' ' -f 3 | xargs -I {} cp {} ./deps/

cd -

rm -rf apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
rm -rf apps/multiplatform/desktop/build/cmake

mkdir -p apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
cp -r $BUILD_DIR/build/deps/* apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
cp $BUILD_DIR/build/libzero.so apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
scripts/desktop/prepare-vlc-linux.sh

links_dir=apps/multiplatform/build/links
mkdir -p $links_dir
cd $links_dir
ln -sfT ../../common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/ $OS-$COMPOSE_ARCH
