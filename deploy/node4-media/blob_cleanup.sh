#!/usr/bin/env bash
# Evict XFTP blobs older than 24h (1440m) and trim oldest entries once volume usage hits 60%.

set -euo pipefail

BLOB_DIR="/mnt/zero-blobs"
MAX_PCT=60

mkdir -p "$BLOB_DIR"

find "$BLOB_DIR" -type f -mmin +1440 -delete

USAGE=$(df -P "$BLOB_DIR" | awk 'NR==2 {gsub("%",""); print $5}')
while [ "${USAGE:-0}" -ge "$MAX_PCT" ]; do
  OLDEST=$(find "$BLOB_DIR" -type f -printf '%T@ %p\n' | awk 'BEGIN{min=""} !min || $1 < min {min=$1; p=substr($0, index($0," ")+1)} END{if (p!="") print p}')
  [ -z "$OLDEST" ] && break
  rm -f "$OLDEST"
  USAGE=$(df -P "$BLOB_DIR" | awk 'NR==2 {gsub("%",""); print $5}')
done
