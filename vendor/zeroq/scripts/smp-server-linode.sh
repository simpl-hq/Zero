#!/bin/bash

exec &> >(tee -i /var/log/stackscript.log)

cd $HOME

sudo DEBIAN_FRONTEND=noninteractive \
  apt-get \
  -o Dpkg::Options::=--force-confold \
  -o Dpkg::Options::=--force-confdef \
  -y --allow-downgrades --allow-remove-essential --allow-change-held-packages \
  update

sudo DEBIAN_FRONTEND=noninteractive \
  apt-get \
  -o Dpkg::Options::=--force-confold \
  -o Dpkg::Options::=--force-confdef \
  -y --allow-downgrades --allow-remove-essential --allow-change-held-packages \
  dist-upgrade

sudo DEBIAN_FRONTEND=noninteractive \
  apt-get \
  -o Dpkg::Options::=--force-confold \
  -o Dpkg::Options::=--force-confdef \
  -y --allow-downgrades --allow-remove-essential --allow-change-held-packages \
  install jq

echo "y" | ufw enable

ufw allow ssh
ufw allow https
ufw allow 5223

echo 'fs.file-max = 1000000' >> /etc/sysctl.conf
echo 'fs.inode-max = 1000000' >> /etc/sysctl.conf
echo 'root soft nofile unlimited' >> /etc/security/limits.conf
echo 'root hard nofile unlimited' >> /etc/security/limits.conf

bin_dir="/opt/zero/bin"
binary="$bin_dir/smp-server"
mkdir -p $bin_dir
curl -L -o $binary https://github.com/simpl-hq/zero/releases/latest/download/smp-server-ubuntu-20_04-x86-64
chmod +x $binary

cat > /etc/profile.d/zero.sh << EOF
#!/bin/bash

export PATH="$PATH:$bin_dir"

EOF

source /etc/profile.d/zero.sh
smp-server --version

init_opts=()

[[ $ENABLE_STORE_LOG == "on" ]] && init_opts+=(-l)

init_opts+=(--disable-web)

ip_address=$(curl ifconfig.me)
init_opts+=(--ip $ip_address)

[[ -n "$FQDN" ]] && init_opts+=(-n $FQDN)

smp-server init "${init_opts[@]}"

fingerprint=$(cat /etc/opt/zero/fingerprint)

if [[ -n "$FQDN" ]]; then
  server_address=$FQDN
else
  server_address=$ip_address
fi

on_login_script="/opt/zero/on_login.sh"

cat > $on_login_script << EOF
#!/bin/bash

fingerprint=\$1
server_address=\$2

cat << EOF2
********************************************************************************

SMP server address: smp://\$fingerprint@\$server_address
Check SMP server status with: systemctl status smp-server

To keep this server secure, the UFW firewall is enabled.
All ports are BLOCKED except 22 (SSH), 443 (HTTPS), 5223 (SMP server).

Embedded HTTPS web is disabled because this script does not provision
/etc/opt/zero/web.crt or /etc/opt/zero/web.key. To enable it, provision
those files, uncomment WEB https/cert/key in /etc/opt/zero/smp-server.ini,
and restart smp-server.

********************************************************************************
To stop seeing this message delete line - bash /opt/zero/on_login.sh - from /root/.bashrc
EOF2

EOF

chmod +x $on_login_script
echo "bash $on_login_script $fingerprint $server_address" >> /root/.bashrc

if [[ -n "$API_TOKEN" ]]; then
  if [[ -n "$FQDN" ]]; then
    domain_address=$(echo $FQDN | rev | cut -d "." -f 1,2 | rev)
    domain_id=$(curl -H "Authorization: Bearer $API_TOKEN" https://api.linode.com/v4/domains \
    | jq --arg da "$domain_address" '.data[] | select( .domain == $da ) | .id')
    if [[ -n $domain_id ]]; then
      curl \
        -s -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_TOKEN" \
        -X POST -d "{\"type\":\"A\",\"name\":\"$FQDN\",\"target\":\"$ip_address\"}" \
        https://api.linode.com/v4/domains/${domain_id}/records
    fi
  fi

  version=$(smp-server --version | cut -d ' ' -f 3-)

  curl \
    -s -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_TOKEN" \
    -X PUT -d "{\"tags\":[\"$server_address\",\"$fingerprint\",\"$version\"]}" \
    https://api.linode.com/v4/linode/instances/$LINODE_ID
fi

cat > /etc/systemd/system/smp-server.service << EOF
[Unit]
Description=SMP server

[Service]
Type=simple
ExecStart=/bin/sh -c "exec $binary start >> /var/opt/zero/smp-server.log 2>&1"
KillSignal=SIGINT
TimeoutStopSec=infinity
Restart=always
RestartSec=10
LimitNOFILE=1000000
LimitNOFILESoft=1000000

[Install]
WantedBy=multi-user.target

EOF

chmod 644 /etc/systemd/system/smp-server.service
sudo systemctl enable smp-server
sudo systemctl start smp-server

sudo reboot
