#!/usr/bin/env sh

# reproducible Linux CLI/Desktop release verification script

set -eu

TAG="$1"

tempdir="$(mktemp -d)"
init_dir="$PWD"

ghc='9.6.3'

repo_name="zero-runtime"
repo="https://github.com/simpl-hq/zero"

image_name='zero-local'
container_name='zero-builder'

cabal_local='ignore-project: False
package direct-sqlcipher
    flags: +openssl'

export DOCKER_BUILDKIT=1

version=${TAG#v}
version=${version%-*}

cleanup() {
    docker exec -t "${container_name}" sh -c 'rm -rf ./dist-newstyle ./apps' 2>/dev/null || :
    rm -rf -- "${tempdir}"
    docker rm --force "${container_name}" 2>/dev/null || :
    docker image rm "${image_name}" 2>/dev/null || :
    cd "${init_dir}"
}
trap 'cleanup' EXIT INT

mkdir -p "${init_dir}/${TAG}-${repo_name}/from-source" "${init_dir}/${TAG}-${repo_name}/prebuilt"

git -C "${tempdir}" clone "${repo}.git" "${repo_name}" && \
    cd "${tempdir}/${repo_name}" && \
    git checkout "${TAG}" && \
    git submodule update --init --recursive

oses="22.04@sha256:5c8b2c0a6c745bc177669abfaa716b4bc57d58e2ea3882fb5da67f4d59e3dda5 24.04@sha256:98ff7968124952e719a8a69bb3cccdd217f5fe758108ac4f21ad22e1df44d237"

for os_pair in ${oses}; do
    os="${os_pair%@*}"
    hash="${os_pair#*@}"
    os_url="$(printf '%s' "${os}" | tr '.' '_')"

    cli_name="zero-runtime-ubuntu-${os_url}-x86_64"
    deb_name="zero-desktop-ubuntu-${os_url}-x86_64.deb"
    appimage_name="zero-desktop-x86_64.AppImage"

    docker build \
        --no-cache \
        --build-arg TAG="${os}" \
        --build-arg HASH="${hash}" \
        --build-arg GHC="${ghc}" \
        --build-arg=USER_UID="$(id -u)" \
        --build-arg=USER_GID="$(id -g)" \
        -f "${tempdir}/${repo_name}/Dockerfile.build" \
        -t "${image_name}" \
        .

    printf '%s' "${cabal_local}" > "${tempdir}/${repo_name}/cabal.project.local"

    docker run -t -d \
        --name "${container_name}" \
        --device /dev/fuse \
        --cap-add SYS_ADMIN \
        --security-opt apparmor:unconfined \
        -v "${tempdir}/${repo_name}:/project" \
        "${image_name}"

    docker exec \
        -t "${container_name}" \
        sh -c 'find /project -type d -exec chmod 755 {} \; ; find /project -type f -perm /111 -exec chmod 755 {} \; ; find /project -type f ! -perm /111 -exec chmod 644 {} \;'

    docker exec \
        -t "${container_name}" \
        sh -c 'cabal clean && cabal update && cabal build -j && mkdir -p /out && for i in zero-runtime; do bin=$(find /project/dist-newstyle -name "$i" -type f -executable) && chmod +x "$bin" && mv "$bin" /out/; done && strip /out/zero-runtime'

    docker cp \
        "${container_name}":/out/zero-runtime \
        "${init_dir}/${TAG}-${repo_name}/from-source/${cli_name}"

    curl -L \
        --output-dir "${init_dir}/${TAG}-${repo_name}/prebuilt/" \
        -O "${repo}/releases/download/${TAG}/${cli_name}"

    docker exec \
        -t "${container_name}" \
        sh -c "./scripts/desktop/build-cli-deb.sh ${version}"

    docker cp \
        "${container_name}":/out/deb-build/zero-runtime.deb \
        "${init_dir}/${TAG}-${repo_name}/from-source/${cli_name}.deb"

    curl -L \
        --output-dir "${init_dir}/${TAG}-${repo_name}/prebuilt/" \
        -O "${repo}/releases/download/${TAG}/${cli_name}.deb"

    docker exec \
        -t "${container_name}" \
        sh -c "export ASSETS_DIR='../../assets'; ./scripts/desktop/make-deb-linux.sh"

    docker cp \
        "${container_name}":/project/apps/multiplatform/release/main/deb/zero_x86_64.deb \
        "${init_dir}/${TAG}-${repo_name}/from-source/${deb_name}"

    curl -L \
        --output-dir "${init_dir}/${TAG}-${repo_name}/prebuilt/" \
        -O "${repo}/releases/download/${TAG}/${deb_name}"

    case "$os" in
        22.04)
            docker exec \
                -t "${container_name}" \
                sh -c "export ASSETS_DIR='../../assets'; ./scripts/desktop/make-appimage-linux.sh && mv ./apps/multiplatform/release/main/*.AppImage ./apps/multiplatform/release/main/zero.appimage"

            docker cp \
                "${container_name}":/project/apps/multiplatform/release/main/zero.appimage \
                "${init_dir}/${TAG}-${repo_name}/from-source/${appimage_name}"

            curl -L \
                --output-dir "${init_dir}/${TAG}-${repo_name}/prebuilt/" \
                -O "${repo}/releases/download/${TAG}/${appimage_name}"
            ;;
    esac

    docker exec \
        -t "${container_name}" \
        sh -c 'rm -rf ./dist-newstyle ./apps/multiplatform'

    git reset --hard && git clean -dfx
    git submodule update --init --recursive

    docker stop "${container_name}"
    docker rm --force "${container_name}"
    docker image rm "${image_name}"
done

rm -rf -- "${tempdir}"
cd "${init_dir}"

path_bin="${init_dir}/${TAG}-${repo_name}"

bad=0

for file in "${path_bin}"/from-source/*; do
    app="$(basename ${file})"

    compiled=$(sha256sum "${path_bin}/from-source/${app}" | awk '{print $1}')
    prebuilt=$(sha256sum "${path_bin}/prebuilt/${app}" | awk '{print $1}')

    if [ "${compiled}" != "${prebuilt}" ]; then
        bad=1

        printf "%s - sha256sum hash doesn't match\n" "${app}"
    fi
done

if [ "${bad}" = 0 ]; then
    sha256sum "${path_bin}"/from-source/* | sed -e "s|$PWD/||g" -e 's|from-source/||g' -e "s|-$repo_name||g" > "${path_bin}/_sha256sums"

    printf 'Checksums computed - %s\n' "${path_bin}/_sha256sums"
fi
