#!/usr/bin/env sh
set -eu

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
export PATH

# links to scripts/configs
scripts="https://raw.githubusercontent.com/simpl-hq/zero/main/vendor/zeroq/scripts/main"
scripts_systemd_smp="$scripts/smp-server.service"
scripts_systemd_xftp="$scripts/xftp-server.service"
scripts_update="$scripts/zero-servers-update"
scripts_uninstall="$scripts/zero-servers-uninstall"
scripts_stopscript="$scripts/zero-servers-stopscript"

# default installation paths
path_bin="/usr/local/bin"
path_bin_smp="$path_bin/smp-server"
path_bin_xftp="$path_bin/xftp-server"
path_bin_update="$path_bin/zero-servers-update"
path_bin_uninstall="$path_bin/zero-servers-uninstall"
path_bin_stopscript="$path_bin/zero-servers-stopscript"

path_conf_etc="/etc/opt"
path_conf_var="/var/opt"
path_conf_smp="$path_conf_etc/zero $path_conf_var/zero"
path_conf_xftp="$path_conf_etc/zero-xftp $path_conf_var/zero-xftp /srv/xftp"

path_conf_info="$path_conf_etc/zero-info"

path_systemd="/etc/systemd/system"
path_systemd_smp="$path_systemd/smp-server.service"
path_systemd_xftp="$path_systemd/xftp-server.service"

# Default system users
user_smp="smp"
user_xftp="xftp"

GRN='\033[0;32m'
BLU='\033[1;34m'
YLW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

logo='
  ________ ____   ___
 |___  / __| _ \ / _ \
    / /| _||   /| (_) |
   /_/ |___|_|_\ \___/
'

welcome="Welcome to SMP/XFTP installation script! Here's what we're going to do:
${GRN}1.${NC} Install latest binaries from GitHub releases:
    - smp: ${YLW}${path_bin_smp}${NC}
    - xftp: ${YLW}${path_bin_xftp}${NC}
${GRN}2.${NC} Create server directories:
    - smp: ${YLW}${path_conf_smp}${NC}
    - xftp: ${YLW}${path_conf_xftp}${NC}
${GRN}3.${NC} Setup user for server:
    - smp: ${YLW}${user_smp}${NC}
    - xftp: ${YLW}${user_xftp}${NC}
${GRN}4.${NC} Create systemd services:
    - smp: ${YLW}${path_systemd_smp}${NC}
    - xftp: ${YLW}${path_systemd_xftp}${NC}
${GRN}5.${NC} Install stopscript (systemd), update and uninstallation script:
    - all: ${YLW}${path_bin_update}${NC}, ${YLW}${path_bin_uninstall}${NC}, ${YLW}${path_bin_stopscript}${NC}

Press:
  - ${GRN}1${NC} to install smp server
  - ${GRN}2${NC} to install xftp server
  - ${RED}Ctrl+C${NC} to cancel installation
  
Selection: "

end="Installation is complete!

Please check out our guides and documentation:
- README: ${GRN}https://github.com/simpl-hq/zero/blob/main/README.md
- Whitepaper: ${GRN}https://github.com/simpl-hq/zero/blob/main/WHITEPAPER.md

To uninstall with full clean-up, simply run: ${YLW}sudo /usr/local/bin/zero-servers-uninstall${NC}
"

set_version() {
  ver="${VER:-latest}"

  case "$ver" in 
    latest)
      bin="https://github.com/simpl-hq/zero/releases/latest/download"
      remote_version="$(curl --proto '=https' --tlsv1.2 -sSf -L https://api.github.com/repos/simpl-hq/zero/releases/latest | grep -i "tag_name" | awk -F \" '{print $4}')"
      ;;
    *)
      bin="https://github.com/simpl-hq/zero/releases/download/${ver}"
      remote_version="${ver}"
      ;;
  esac
}

os_test() {
 . /etc/os-release

 distro="${ID:-}"
 version_id="${VERSION_ID:-}"
 codename="${VERSION_CODENAME:-}"

 case "$distro" in
  ubuntu)
   case "$version_id" in
    20.04|22.04) : ;;
    24.04) version_id='22.04' ;;
    *) printf "${RED}Unsupported Ubuntu version!${NC}\nPlease file GitHub issue with request to support Ubuntu %s: https://github.com/simpl-hq/zero/issues/new\n" "${version_id:-unknown}" && exit 1 ;;
   esac
   version="$(printf '%s' "$version_id" | tr '.' '_')"
   ;;
  debian)
   case "${version_id:-$codename}" in
    13|13.*|trixie) version='13' ;;
    *) printf "${RED}Unsupported Debian version!${NC}\nPlease file GitHub issue with request to support Debian %s: https://github.com/simpl-hq/zero/issues/new\n" "${version_id:-${codename:-unknown}}" && exit 1 ;;
   esac
   ;;
  *)
   printf "${RED}Unsupported Linux distribution!${NC}\nPlease file GitHub issue with request to support %s: https://github.com/simpl-hq/zero/issues/new\n" "${distro:-unknown}" && exit 1
   ;;
 esac

 arch="$(uname -m)"

 case "$arch" in
  x86_64) arch='x86-64' ;;
  aarch64|arm64) arch='aarch64' ;;
  *) printf "${RED}Unsupported architecture!${NC}\nPlease file GitHub issue with request to support %s architecture: https://github.com/simpl-hq/zero/issues/new\n" "$arch" && exit 1 ;;
 esac

 bin_smp="$bin/smp-server-${distro}-${version}-${arch}"
 bin_xftp="$bin/xftp-server-${distro}-${version}-${arch}"
}

setup_deps() {
 if command -v apt-get >/dev/null 2>&1; then
  if ! dpkg -s libnuma1 libgmp10 zlib1g >/dev/null 2>&1 || \
     { ! dpkg -s libssl3t64 >/dev/null 2>&1 && ! dpkg -s libssl3 >/dev/null 2>&1; }; then
   DEBIAN_FRONTEND=noninteractive apt-get update -qq
   DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libnuma1 libgmp10 zlib1g
   DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libssl3t64 || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libssl3
  fi
 fi
}

setup_bins() {
 eval "bin=\$bin_${1}"
 eval "path=\$path_bin_${1}"

 curl --proto '=https' --tlsv1.2 -sSf -L "$bin" -o "$path" && chmod +x "$path"

 unset bin path
}

setup_users() {
 eval "user=\$user_${1}"

 useradd -M "$user" 2> /dev/null || true

 unset user
}

setup_dirs() {
 # unquoted varibles, so field splitting can occur
 eval "path_conf=\$path_conf_${1}"
 eval "user=\$user_${1}"

 mkdir -p $path_conf
 mkdir -p $path_conf_info
 printf "local_version_%s='%s'\n" "$1" "$remote_version" >> "$path_conf_info/release"
 chown -R "$user":"$user" $path_conf

 unset path_conf user
}

setup_systemd() {
 eval "scripts_systemd=\$scripts_systemd_${1}"
 eval "path_systemd=\$path_systemd_${1}"

 curl --proto '=https' --tlsv1.2 -sSf -L "$scripts_systemd" -o "$path_systemd"

 unset scripts_systemd path_systemd
}

setup_scripts() {
 curl --proto '=https' --tlsv1.2 -sSf -L "$scripts_update" -o "$path_bin_update" && chmod +x "$path_bin_update"
 curl --proto '=https' --tlsv1.2 -sSf -L "$scripts_uninstall" -o "$path_bin_uninstall" && chmod +x "$path_bin_uninstall"
 curl --proto '=https' --tlsv1.2 -sSf -L "$scripts_stopscript" -o "$path_bin_stopscript" && chmod +x "$path_bin_stopscript"
 }

checks() {
 if [ "$(id -u)" -ne 0 ]; then
  printf "This script is intended to be run with root privileges. Please re-run script using sudo."
  exit 1
 fi
 
 set_version
 os_test

 mkdir -p $path_conf_info  
}

main() {
 checks
 
 printf "%b\n%b" "${BLU}$logo${NC}" "$welcome"
 read ans

 case "$ans" in
  1) setup='smp' ;;
  2) setup='xftp' ;;
  *) printf 'Installation aborted.\n' && exit 0 ;;
 esac

 printf "Checking runtime dependencies..."
 setup_deps
 printf "${GRN} Done!${NC}\n"

 printf "Installing binaries..."
 
 for i in $setup; do
  setup_bins "$i"
 done
 
 printf "${GRN} Done!${NC}\n"

 printf "Creating users..."

 for i in $setup; do
  setup_users "$i"
 done

 printf "${GRN} Done!${NC}\n"
 
 printf "Creating directories..."

 for i in $setup; do
  setup_dirs "$i"
 done

 printf "${GRN} Done!${NC}\n"

 printf "Creating systemd services..."

 for i in $setup; do
  setup_systemd "$i"
 done

 printf "${GRN} Done!${NC}\n"

 printf "Installing stopscript, update and uninstallation script..."

 setup_scripts

 printf "${GRN} Done!${NC}\n"

 printf "%b" "$end"
}

main
