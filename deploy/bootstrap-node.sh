#!/usr/bin/env bash
# Baseline provisioning for Zero cluster nodes: runtime packages, volatile journald, Docker/WireGuard boot ordering, and UFW rules.

set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

NODE_ROLE="${1:-}"
SSH_PORT="${2:-22}"

if [[ ! "$NODE_ROLE" =~ ^node[1-4]$ ]]; then
  echo "Usage: sudo $0 <node1|node2|node3|node4> [ssh_port]"
  exit 1
fi

case "$NODE_ROLE" in
  node1) WG_IP="10.10.0.1/24" ;;
  node2) WG_IP="10.10.0.2/24" ;;
  node3) WG_IP="10.10.0.3/24" ;;
  node4) WG_IP="10.10.0.4/24" ;;
esac

echo "[*] Bootstrapping Zero cluster $NODE_ROLE ($WG_IP)..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl git gnupg sudo ufw wireguard jq cron cryptsetup

if [ "$NODE_ROLE" = "node1" ] || [ "$NODE_ROLE" = "node2" ] || [ "$NODE_ROLE" = "node4" ]; then
  apt-get install -y libnuma1 libgmp10 zlib1g libpq5
  apt-get install -y libssl3t64 || apt-get install -y libssl3
fi

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

if [ "$NODE_ROLE" != "node4" ] && [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

cat << 'EOF' > /etc/sysctl.d/99-zero-cluster.conf
vm.swappiness = 10
fs.file-max = 2097152
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
EOF
sysctl --system

cat << 'EOF' > /etc/security/limits.d/99-zero.conf
* soft nofile 100000
* hard nofile 100000
root soft nofile 100000
root hard nofile 100000
EOF

mkdir -p /etc/systemd/journald.conf.d
cat << 'EOF' > /etc/systemd/journald.conf.d/zero-cap.conf
[Journal]
Storage=volatile
RuntimeMaxUse=64M
EOF
rm -rf /var/log/journal/*
systemctl restart systemd-journald

mkdir -p /etc/docker
cat << 'EOF' > /etc/docker/daemon.json
{
  "log-driver": "local",
  "log-opts": {
    "max-size": "2m",
    "max-file": "1",
    "compress": "false"
  }
}
EOF
systemctl restart docker

mkdir -p /etc/systemd/system/docker.service.d
cat << 'EOF' > /etc/systemd/system/docker.service.d/99-wireguard.conf
[Unit]
After=wg-quick@wg0.service
EOF
systemctl daemon-reload

mkdir -p /etc/wireguard
chmod 700 /etc/wireguard
if [ ! -f /etc/wireguard/private.key ]; then
  wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
  chmod 600 /etc/wireguard/private.key
fi
echo "[+] WireGuard Public Key for $NODE_ROLE ($WG_IP): $(cat /etc/wireguard/public.key)"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT"/tcp
ufw allow 51820/udp

ufw deny out 25/tcp
ufw deny out 465/tcp
ufw deny out 587/tcp

if [ "$NODE_ROLE" = "node1" ] || [ "$NODE_ROLE" = "node2" ]; then
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 5223/tcp
  ufw allow 3478/tcp
  ufw allow 3478/udp
  ufw allow 5349/tcp
  ufw allow 5349/udp
  ufw allow 49152:65535/udp
  ufw allow in on wg0 from 10.10.0.0/24
elif [ "$NODE_ROLE" = "node3" ]; then
  ufw allow in on wg0 from 10.10.0.0/24 to any port 5432 proto tcp
  ufw allow in on wg0 from 10.10.0.0/24 to any port 6379 proto tcp
  ufw route allow in on wg0 from 10.10.0.0/24 to any port 5432 proto tcp
  ufw route allow in on wg0 from 10.10.0.0/24 to any port 6379 proto tcp
elif [ "$NODE_ROLE" = "node4" ]; then
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 5223/tcp
  ufw allow 3478/tcp
  ufw allow 3478/udp
  ufw allow 5349/tcp
  ufw allow 5349/udp
  ufw allow 49152:65535/udp
  ufw allow in on wg0 from 10.10.0.0/24
fi

ufw --force enable

echo "[+] Bootstrap complete for $NODE_ROLE. Next: populate /etc/wireguard/wg0.conf, .env, and run 'docker compose up -d'."
