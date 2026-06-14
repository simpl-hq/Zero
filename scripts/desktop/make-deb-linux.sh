#!/usr/bin/env sh

ARCH="$(uname -m)"

scripts/desktop/build-lib-linux.sh
cd apps/multiplatform
if [ -n "${ASSETS_DIR:-}" ]; then
  set -- -Pzero.assets.dir="$ASSETS_DIR"
else
  set --
fi
./gradlew "$@" packageDeb

export SOURCE_DATE_EPOCH=1704067200

dpkg-deb -R ./release/main/deb/zero*.deb ./extracted

. /etc/os-release

rm -f ./extracted/opt/zero/lib/app/*skiko-awt-runtime-linux*
sed -i -e '/skiko-awt-runtime-linux/d' ./extracted/opt/zero/lib/app/zero.cfg
sed -i "/Version/ s/\$/~$VERSION_CODENAME/" ./extracted/DEBIAN/control
find ./extracted/ -exec touch -d "@$SOURCE_DATE_EPOCH" {} +

dpkg-deb --build --root-owner-group --uniform-compression ./extracted ./release/main/deb/zero_${ARCH}.deb

strip-nondeterminism ./release/main/deb/zero_${ARCH}.deb
