#!/bin/bash

set -eu

if [[ ! -f /opt/zero/do_initialize_server ]]; then
  touch /opt/zero/do_initialize_server
elif [[ ! -f /etc/opt/zero/smp-server.ini ]]; then
  chmod +x /opt/zero/initialize_server.sh
  /opt/zero/initialize_server.sh
else
  echo "SMP server already initialized"
fi
