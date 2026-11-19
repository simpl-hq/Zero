#!/usr/bin/env sh

set -eu

TAG="$1"

tempdir="$(mktemp -d)"
init_dir="$PWD"

repo_name="zero"
repo="https://github.com/simpl-hq/${repo_name}"
export DOCKER_BUILDKIT=1

cleanup() {
	docker exec -t builder sh -c 'rm -rf /project/vendor/zeroq/dist-newstyle' 2>/dev/null || :
	rm -rf -- "$tempdir"
	docker rm --force builder 2>/dev/null || :
	docker image rm local 2>/dev/null || :
	cd "$init_dir"
}
trap 'cleanup' EXIT INT

mkdir -p "$init_dir/$TAG-$repo_name/from-source" "$init_dir/$TAG-$repo_name/prebuilt"

git -C "$tempdir" clone "$repo.git" &&\
	cd "$tempdir/${repo_name}" &&\
	git checkout "$TAG"

for target in ubuntu:22.04 ubuntu:24.04 debian:trixie; do
	distro="${target%%:*}"
	os="${target#*:}"
	case "${distro}:${os}" in
		debian:trixie) os_url="13" ;;
		*) os_url="$(printf '%s' "$os" | tr '.' '_')" ;;
	esac

	docker build \
		--no-cache \
		--build-arg DISTRO="${distro}" \
		--build-arg TAG="${os}" \
		--build-arg GHC=9.6.3 \
		-f "$tempdir/${repo_name}/vendor/zeroq/Dockerfile.build" \
		-t local \
		.

	docker run -t -d \
		--name builder \
		-v "$tempdir/${repo_name}:/project" \
		local

	docker exec \
		-t \
		builder \
		sh -c 'git config --global --add safe.directory \* && cd /project/vendor/zeroq && cabal update && cabal build --jobs=$(nproc) --enable-tests -fserver_postgres && mkdir -p /out && for i in smp-server zeroq-test; do bin=$(find dist-newstyle -name "$i" -type f -executable) && chmod +x "$bin" && mv "$bin" /out/; done && strip /out/smp-server'

	docker cp \
		builder:/out/smp-server \
		"$init_dir/$TAG-$repo_name/from-source/smp-server-postgres-${distro}-${os_url}-x86-64"

	curl -L \
		--output-dir "$init_dir/$TAG-$repo_name/prebuilt/" \
		-O \
		"$repo/releases/download/${TAG}/smp-server-postgres-${distro}-${os_url}-x86-64"
	
	apps='smp-server xftp-server ntf-server xftp'

	docker exec \
		-t \
		-e apps="$apps" \
		builder \
		sh -c 'cd /project/vendor/zeroq && cabal build --jobs=$(nproc) && mkdir -p /out && for i in $apps; do bin=$(find dist-newstyle -name "$i" -type f -executable) && strip "$bin" && chmod +x "$bin" && mv "$bin" /out/; done'

	docker cp \
		builder:/out \
		"out-${distro}-${os}"
	
	for app in $apps; do
		curl -L \
			--output-dir "$init_dir/$TAG-$repo_name/prebuilt/" \
			-O \
			"$repo/releases/download/${TAG}/${app}-${distro}-${os_url}-x86-64"

		mv "./out-${distro}-${os}/$app" "$init_dir/$TAG-$repo_name/from-source/${app}-${distro}-${os_url}-x86-64"
	done

	docker exec \
		-t \
		builder \
		sh -c 'rm -rf /project/vendor/zeroq/dist-newstyle'

	git reset --hard && git clean -dfx

	docker stop builder
	docker rm --force builder
	docker image rm local
done

rm -rf -- "$tempdir"
cd "$init_dir"

path_bin="$init_dir/$TAG-$repo_name"

bad=0

for file in "$path_bin"/from-source/*; do
	app="$(basename $file)"

	compiled=$(sha256sum "$path_bin/from-source/$app" | awk '{print $1}')
	prebuilt=$(sha256sum "$path_bin/prebuilt/$app" | awk '{print $1}')

	if [ "$compiled" != "$prebuilt" ]; then
		bad=1

		printf "%s - sha256sum hash doesn't match\n" "$app"
	fi
done

if [ "$bad" = 0 ]; then
	sha256sum "$path_bin"/from-source/* | sed -e "s|$PWD/||g" -e 's|from-source/||g' -e "s|-$repo_name||g" > "$path_bin/_sha256sums"

	printf 'Checksums computed - %s\n' "$path_bin/_sha256sums"
fi
