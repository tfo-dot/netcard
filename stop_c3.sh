#!/usr/bin/env bash
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (use: sudo ./stop_c3.sh)"
    exit 1
fi

echo "Stopping SLIP and removing interface..."
pkill -x ldattach 2>/dev/null || true
echo "Done."
