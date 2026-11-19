#!/bin/sh

echo "y" | ufw enable

ufw allow ssh
ufw allow https
ufw allow 5223
