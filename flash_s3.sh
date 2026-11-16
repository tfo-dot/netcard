#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/esp-idf/export.sh"

PORT=""
for p in /dev/ttyACM0 /dev/ttyACM1 /dev/ttyACM2; do
    if [ -e "$p" ]; then
        PORT="$p"
    fi
done

if [ -z "$PORT" ]; then
    echo "Error: No ESP serial port found."
    exit 1
fi

echo "Flashing ESP32-S3 on port $PORT..."
idf.py -C "$DIR/espnow_nic/s3_ncm" -p "$PORT" flash
echo "ESP32-S3 flashing complete!"
