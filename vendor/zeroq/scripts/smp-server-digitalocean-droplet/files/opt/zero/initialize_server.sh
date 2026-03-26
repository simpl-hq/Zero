#!/bin/bash

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

ip_address=$(curl ifconfig.me)
smp-server init -l --disable-web --ip $ip_address

fingerprint=$(cat /etc/opt/zero/fingerprint)

echo "bash /opt/zero/on_login.sh $fingerprint $ip_address" >> /root/.bashrc

cat > /etc/systemd/system/smp-server.service << EOF
[Unit]
Description=SMP server

[Service]
Type=simple
ExecStart=/bin/sh -c "exec $binary start >> /var/opt/zero/smp-server.log 2>&1"

[Install]
WantedBy=multi-user.target

EOF

chmod 644 /etc/systemd/system/smp-server.service
sudo systemctl enable smp-server
sudo systemctl start smp-server
