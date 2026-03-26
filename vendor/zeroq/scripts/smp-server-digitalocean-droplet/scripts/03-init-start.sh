#!/bin/bash

chmod +x /opt/zero/server_bootstrap.sh

cat > /etc/systemd/system/server-bootstrap.service << EOF
[Unit]
Description=Server bootstrap script that downloads and initializes SMP server from the latest release

[Service]
Type=oneshot
ExecStart=/opt/zero/server_bootstrap.sh

[Install]
WantedBy=multi-user.target

EOF

chmod 644 /etc/systemd/system/server-bootstrap.service
sudo systemctl enable server-bootstrap
sudo systemctl start server-bootstrap
