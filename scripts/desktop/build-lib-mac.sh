#!/bin/bash

set -e

OS=mac
ARCH="${1:-$(uname -m)}"
COMPOSE_ARCH=$ARCH
GHC_VERSION=9.6.3
DATABASE_BACKEND="${2:-sqlite}"

if [ "$ARCH" == "arm64" ]; then
    ARCH=aarch64
else
    COMPOSE_ARCH=x64
fi

LIB_EXT=dylib
LIB=libzero.$LIB_EXT
GHC_LIBS_DIR=$(ghc --print-libdir)

BUILD_DIR=dist-newstyle/build/$ARCH-*/ghc-*/zero-runtime-*

exports=( $(awk '/^foreign export ccall / { sym=$4; gsub(/"/, "", sym); if (sym != "zero_core_runtime_migrate_init_key" && sym != "zero_core_runtime_reopen_store") print sym }' src/Zero/Chat/Mobile.hs) )
for elem in "${exports[@]}"; do count=$(grep -R "$elem$" libzero.dll.def | wc -l); if [ $count -ne 1 ]; then echo Wrong exports in libzero.dll.def. Add \"$elem\" to that file; exit 1; fi ; done
for elem in "${exports[@]}"; do count=$(grep -R "\"$elem\"" flake.nix | wc -l); if [ $count -ne 2 ]; then echo Wrong exports in flake.nix. Add \"$elem\" in two places of the file; exit 1; fi ; done

rm -rf $BUILD_DIR

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

cat <<EOF >> "$REPO_ROOT/cabal.project.local"

package zero-runtime
    ghc-options: -optl-Wl,-rpath,@loader_path -optl-Wl,-install_name,@rpath/$LIB -optl-Wl,-L$GHC_LIBS_DIR/$ARCH-osx-ghc-$GHC_VERSION -optl-lHSrts_thr-ghc$GHC_VERSION -optl-lffi
EOF

if [[ "$DATABASE_BACKEND" == "postgres" ]]; then
    echo "Building with postgres backend..."
    cabal build lib:zero-runtime --constraint 'zeroq +client_library +client_postgres' --constraint 'zero-runtime +client_library +client_postgres'
else
    echo "Building with sqlite backend..."
    cabal build lib:zero-runtime --constraint 'zeroq +client_library' --constraint 'zero-runtime +client_library'
fi

cd $BUILD_DIR/build
mv libHSzero-runtime-*-inplace-ghc*.$LIB_EXT libzero.dylib 2> /dev/null || true
mkdir deps 2> /dev/null || true

(
  BUILD=$PWD
  cp /tmp/libffi-3.5.2/*-apple-darwin*/.libs/libffi.dylib $BUILD/deps || \
    ( \
    cd /tmp && \
    curl --tlsv1.2 "https://gitlab.haskell.org/ghc/libffi-tarballs/-/raw/3914c27381526ce586ea0ac0359a332fd82987af/libffi-3.5.2.tar.gz?inline=false" -o libffi.tar.gz && \
    tar -xzvf libffi.tar.gz && \
    cd "libffi-3.5.2" && \
    ./configure && \
    make && \
    cp *-apple-darwin*/.libs/libffi.dylib $BUILD/deps \
    )
)

DYLIBS=`otool -L $LIB | grep @rpath | tail -n +2 | cut -d' ' -f 1 | cut -d'/' -f2`
RPATHS=`otool -l $LIB | grep "path "| cut -d' ' -f11`

PROCESSED_LIBS=()

function copy_deps() {
    local LIB=$1
    if [[ "${PROCESSED_LIBS[*]}" =~ "$LIB" ]]; then
    	return 0
    fi

    PROCESSED_LIBS+=$LIB
	local DYLIBS=`otool -L $LIB | grep @rpath | tail -n +2 | cut -d' ' -f 1 | cut -d'/' -f2`
	local NON_FINAL_RPATHS=`otool -l $LIB | grep "path "| cut -d' ' -f11`
	local RPATHS=`otool -l $LIB | grep "path "| cut -d' ' -f11 | sed "s|@loader_path/..|$GHC_LIBS_DIR|"`

	cp "$LIB" ./deps
	chmod u+w "./deps/$(basename "$LIB")"
	install_name_tool -add_rpath @loader_path "./deps/$(basename "$LIB")" 2>/dev/null || true

	for DYLIB in $DYLIBS; do
	    for RPATH in $RPATHS; do
	        if [ -f "$RPATH/$DYLIB" ]; then
	            if [ ! -f "deps/$DYLIB" ]; then
	            	cp "$RPATH/$DYLIB" ./deps
	            fi
	            copy_deps "$RPATH/$DYLIB"
	        fi
	    done
	done
}

copy_deps $LIB
cp $(ghc --print-libdir)/$ARCH-osx-ghc-$GHC_VERSION/libHSghc-boot-th-$GHC_VERSION-ghc$GHC_VERSION.dylib deps
rm deps/`basename $LIB`

cd -

rm -rf apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
rm -rf apps/multiplatform/desktop/build/cmake

mkdir -p apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
cp -r $BUILD_DIR/build/deps/* apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/
cp $BUILD_DIR/build/$LIB apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/

cd apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/

LIBCRYPTO_SRC=""
for dylib in *."$LIB_EXT"; do
    [ -f "$dylib" ] || continue
    [ "$dylib" = "libcrypto.3.0.$LIB_EXT" ] && continue
    chmod u+w "$dylib"
    while IFS= read -r LIBCRYPTO_PATH; do
        [ -n "$LIBCRYPTO_PATH" ] || continue
        if [ -z "$LIBCRYPTO_SRC" ] && [ -f "$LIBCRYPTO_PATH" ]; then
            LIBCRYPTO_SRC="$LIBCRYPTO_PATH"
            cp "$LIBCRYPTO_SRC" "libcrypto.3.0.$LIB_EXT"
            chmod 755 "libcrypto.3.0.$LIB_EXT"
            install_name_tool -id "@rpath/libcrypto.3.0.$LIB_EXT" "libcrypto.3.0.$LIB_EXT"
        fi
        install_name_tool -change "$LIBCRYPTO_PATH" "@rpath/libcrypto.3.0.$LIB_EXT" "$dylib"
    done < <(otool -L "$dylib" | awk '/libcrypto/ && $1 !~ /:$/ {print $1}')
done
chmod u+w "libffi.$LIB_EXT" 2>/dev/null || true
install_name_tool -id "libffi.8.$LIB_EXT" "libffi.$LIB_EXT"

for lib in $(find . -type f -name "*.$LIB_EXT"); do
    chmod u+w "$lib"
    RPATHS=$(otool -l "$lib" | grep -E "path /Users/|path /usr/local|path /opt/" | cut -d' ' -f11 || true)
    for RPATH in $RPATHS; do
        install_name_tool -delete_rpath "$RPATH" "$lib" || true
    done
done

LOCAL_DIRS=`for lib in $(find . -type f -name "*.$LIB_EXT"); do otool -l $lib | grep -E "/Users|/opt/|/usr/local" && echo $lib || true; done`
if [ -n "$LOCAL_DIRS" ]; then
    echo These libs still point to local directories:
    echo $LOCAL_DIRS
    if [[ "$DATABASE_BACKEND" == "sqlite" ]]; then
        exit 1
    fi
fi

cd -
scripts/desktop/prepare-vlc-mac.sh
bash scripts/desktop/prepare-tor.sh macos "$ARCH" "apps/multiplatform/common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/tor"

links_dir=apps/multiplatform/build/links
mkdir -p $links_dir
cd $links_dir
rm macos-$COMPOSE_ARCH 2>/dev/null | true
ln -sf ../../common/src/commonMain/cpp/desktop/libs/$OS-$ARCH/ macos-$COMPOSE_ARCH
