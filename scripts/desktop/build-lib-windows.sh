#!/bin/bash

set -e

function readlink() {
  echo "$(cd "$(dirname "$1")"; pwd -P)"
}
root_dir="$(dirname "$(dirname "$(readlink "$0")")")"

OS=windows
ARCH=${1:-x86_64}
if [ "$ARCH" == "aarch64" ]; then
    COMPOSE_ARCH=arm64
else
    COMPOSE_ARCH=x64
fi

BUILD_DIR=dist-newstyle/build/$ARCH-$OS/ghc-*/zero-runtime-*

exports=( $(awk '/^foreign export ccall / { sym=$4; gsub(/"/, "", sym); if (sym != "zero_core_runtime_migrate_init_key" && sym != "zero_core_runtime_reopen_store") print sym }' src/Zero/Chat/Mobile.hs) )
for elem in "${exports[@]}"; do count=$(grep -R "$elem$" libzero.dll.def | wc -l); if [ $count -ne 1 ]; then echo Wrong exports in libzero.dll.def. Add \"$elem\" to that file; exit 1; fi ; done
for elem in "${exports[@]}"; do count=$(grep -R "\"$elem\"" flake.nix | wc -l); if [ $count -ne 2 ]; then echo Wrong exports in flake.nix. Add \"$elem\" in two places of the file; exit 1; fi ; done

cd $root_dir
mkdir dist-newstyle 2>/dev/null || true

scripts/desktop/prepare-openssl-windows.sh

openssl_windows_style_path=$(echo `pwd`/dist-newstyle/openssl-3.0.15 | sed 's#/\([a-zA-Z]\)#\1:#' | sed 's#/#\\#g')
rm -rf $BUILD_DIR 2>/dev/null || true
rm -rf dist-newstyle/src/direct-sq* dist-newstyle/src/zeroq* 2>/dev/null || true
rm cabal.project.local 2>/dev/null || true
echo "ignore-project: False" >> cabal.project.local
echo "package zeroq" >> cabal.project.local
echo "    extra-include-dirs: $openssl_windows_style_path\include" >> cabal.project.local
echo "    extra-lib-dirs: $openssl_windows_style_path" >> cabal.project.local
echo "package direct-sqlcipher" >> cabal.project.local
echo "    flags: +openssl" >> cabal.project.local
echo "    extra-include-dirs: $openssl_windows_style_path\include" >> cabal.project.local
echo "    extra-lib-dirs: $openssl_windows_style_path" >> cabal.project.local
echo "package zero-runtime" >> cabal.project.local
echo "    ghc-options: -shared -threaded -optl-L$openssl_windows_style_path -optl-lcrypto-3-x64 -o libzero.dll libzero.dll.def" >> cabal.project.local
ghc_libdir="$(cygpath -u "$(ghc --print-libdir)")"
sed -i "s/ld.lld.exe/abracadabra.exe/" "$ghc_libdir/settings"
cabal build lib:zero-runtime --constraint 'zeroq +client_library' --constraint 'zero-runtime +client_library'

rm -rf apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
rm -rf apps/multiplatform/desktop/build/cmake

mkdir -p apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
cp dist-newstyle/openssl-3.0.15/libcrypto-3-x64.dll apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
cp libzero.dll apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/

scripts/desktop/prepare-vlc-windows.sh
bash scripts/desktop/prepare-tor.sh windows "$ARCH" "apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/tor"

links_dir=apps/multiplatform/build/links
mkdir -p $links_dir
cd $links_dir
rm -rf $OS-$COMPOSE_ARCH
if ! ln -sfT ../../common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/ $OS-$COMPOSE_ARCH 2>/dev/null || [ ! -d "$OS-$COMPOSE_ARCH" ]; then
  rm -rf $OS-$COMPOSE_ARCH
  mkdir -p $OS-$COMPOSE_ARCH
  cp -r ../../common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/. $OS-$COMPOSE_ARCH/
fi
