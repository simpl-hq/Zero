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

bin_dir="/opt/zero-notifications/bin"
binary="$bin_dir/ntf-server"
mkdir -p $bin_dir
curl -L -o $binary https://github.com/simpl-hq/zero/releases/latest/download/ntf-server-ubuntu-20_04-x86-64
chmod +x $binary

cat > /etc/profile.d/zero.sh << EOF
#!/bin/bash

export PATH="$PATH:$bin_dir"

EOF

source /etc/profile.d/zero.sh
ntf-server --version

init_opts=()

[[ $ENABLE_STORE_LOG == "on" ]] && init_opts+=(-l)

ip_address=$(curl ifconfig.me)
init_opts+=(--ip $ip_address)

[[ -n "$FQDN" ]] && init_opts+=(-n $FQDN)

ntf-server init "${init_opts[@]}"

fingerprint=$(cat /etc/opt/zero-notifications/fingerprint)

if [[ -n "$FQDN" ]]; then
  server_address=$FQDN
else
  server_address=$ip_address
fi

on_login_script="/opt/zero-notifications/on_login.sh"

cat > $on_login_script << EOF
#!/bin/bash

fingerprint=\$1
server_address=\$2

cat << EOF2
********************************************************************************

Zero notifications server address: ntf://\$fingerprint@\$server_address
Check server status with: systemctl status ntf-server

To keep this server secure, the UFW firewall is enabled.
All ports are BLOCKED except 22 (SSH), 443 (HTTPS), 5223 (notifications server).

********************************************************************************
To stop seeing this message delete line - bash /opt/zero-notifications/on_login.sh - from /root/.bashrc
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

  version=$(ntf-server --version | cut -d ' ' -f 3-)

  curl \
    -s -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_TOKEN" \
    -X PUT -d "{\"tags\":[\"$server_address\",\"$fingerprint\",\"$version\"]}" \
    https://api.linode.com/v4/linode/instances/$LINODE_ID
fi

cat > /etc/systemd/system/ntf-server.service << EOF
[Unit]
Description=Zero notifications server

[Service]
Environment="APNS_KEY_FILE=/etc/opt/zero-notifications/AuthKey.p8"
Environment="APNS_KEY_ID=$APNS_KEY_ID"
Type=simple
ExecStart=/bin/sh -c "exec $binary start >> /var/opt/zero-notifications/ntf-server.log 2>&1"
KillSignal=SIGINT
Restart=always
RestartSec=10
LimitNOFILE=1000000
LimitNOFILESoft=1000000

[Install]
WantedBy=multi-user.target

EOF

chmod 644 /etc/systemd/system/ntf-server.service
sudo systemctl enable ntf-server

