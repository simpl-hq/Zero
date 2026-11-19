#!/usr/bin/env bash

set -e

ARCH="$(uname -m)"

function readlink() {
  echo "$(cd "$(dirname "$1")"; pwd -P)"
}

root_dir="$(dirname "$(dirname "$(readlink "$0")")")"
multiplatform_dir=$root_dir/apps/multiplatform
release_app_dir=$root_dir/apps/multiplatform/release/main/app

cd $multiplatform_dir
libcrypto_path=$(ldd common/src/commonMain/cpp/desktop/libs/*/libHSdirect-sqlcipher-*.so | grep libcrypto | cut -d'=' -f 2 | cut -d ' ' -f 2)
trap "rm common/src/commonMain/cpp/desktop/libs/*/`basename $libcrypto_path` 2> /dev/null || true" EXIT
cp $libcrypto_path common/src/commonMain/cpp/desktop/libs/*

if [ -n "${ASSETS_DIR:-}" ]; then
  set -- -Pzero.assets.dir="$ASSETS_DIR"
else
  set --
fi
./gradlew "$@" createDistributable
rm common/src/commonMain/cpp/desktop/libs/*/`basename $libcrypto_path`

rm -rf $release_app_dir/AppDir 2>/dev/null
mkdir -p $release_app_dir/AppDir/usr

cd $release_app_dir/AppDir
cp -r ../zero/{bin,lib} usr
cp usr/lib/zero.png .

mkdir -p usr/share/{icons,metainfo,applications}
cp usr/lib/zero.png usr/share/icons

ln -s usr/bin/zero AppRun
cp $multiplatform_dir/desktop/src/jvmMain/resources/distribute/Zero.desktop app.zero.chat.desktop
sed -i 's|Exec=.*|Exec=zero|g' app.zero.chat.desktop
sed -i 's|Icon=.*|Icon=zero|g' app.zero.chat.desktop
cp app.zero.chat.desktop usr/share/applications/
cp $multiplatform_dir/desktop/src/jvmMain/resources/distribute/*.appdata.xml usr/share/metainfo

if [ ! -f ../appimagetool-${ARCH}.AppImage ]; then
    wget --secure-protocol=TLSv1_3 https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH}.AppImage -O ../appimagetool-${ARCH}.AppImage
    chmod +x ../appimagetool-${ARCH}.AppImage
fi
if [ ! -f ../runtime-${ARCH} ]; then
    wget --secure-protocol=TLSv1_3 https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-${ARCH} -O ../runtime-${ARCH}
    chmod +x ../runtime-${ARCH}
fi

export SOURCE_DATE_EPOCH=1704067200

rm -f ./usr/lib/app/*skiko-awt-runtime-linux*
sed -i -e '/skiko-awt-runtime-linux/d' ./usr/lib/app/zero.cfg

find . -exec touch -d "@$SOURCE_DATE_EPOCH" {} +

../appimagetool-${ARCH}.AppImage --verbose --no-appstream --runtime-file ../runtime-${ARCH} .
mv *.AppImage ../../

strip-nondeterminism ../../*.AppImage
