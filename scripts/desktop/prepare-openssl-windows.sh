#!/bin/bash

set -e

function readlink() {
  echo "$(cd "$(dirname "$1")"; pwd -P)"
}
root_dir="$(dirname "$(dirname "$(readlink "$0")")")"

cd $root_dir

if [ ! -f dist-newstyle/openssl-3.0.15/libcrypto-3-x64.dll ]; then
    mkdir dist-newstyle 2>/dev/null || true
    cd dist-newstyle
    curl --tlsv1.2 https://www.openssl.org/source/openssl-3.0.15.tar.gz -L -o openssl.tar.gz
    tar_bin="$(cygpath -u "${WINDIR:-C:/Windows}")/System32/tar.exe"
    [ -x "$tar_bin" ] || tar_bin=tar
    "$tar_bin" -xvzf openssl.tar.gz
    cd openssl-3.0.15
    ./Configure mingw64
    make -j$(nproc)
    cd ../../
fi
