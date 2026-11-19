#!/bin/bash

curl -L -o /opt/zero/bin/smp-server-new https://github.com/simpl-hq/zero/releases/latest/download/smp-server-ubuntu-20_04-x86-64
systemctl stop smp-server
cp /var/opt/zero/smp-server-store.log /var/opt/zero/smp-server-store.log.bak
mv /opt/zero/bin/smp-server /opt/zero/bin/smp-server-old
mv /opt/zero/bin/smp-server-new /opt/zero/bin/smp-server
chmod +x /opt/zero/bin/smp-server
systemctl start smp-server
