#!/usr/bin/env bash
set -e

PORT="/dev/ttyACM0"
if [ ! -e "$PORT" ]; then
    if [ -e "/dev/ttyACM1" ]; then
        PORT="/dev/ttyACM1"
    else
        echo "Error: Neither /dev/ttyACM0 nor /dev/ttyACM1 found."
        exit 1
    fi
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (use: sudo ./setup_c3.sh)"
    exit 1
fi

echo "Using port: $PORT"

pkill -x ldattach 2>/dev/null || true
sleep 0.5

stty -F "$PORT" raw -echo -echoe -echok -echoctl -echoke -hupcl 921600

echo "Attaching SLIP interface on $PORT..."
ldattach -s 921600 -8 -n -1 SLIP "$PORT"
sleep 1

# Find the sl interface (sl0, sl1, etc.)
SL_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^sl[0-9]+' | head -n1)
if [ -z "$SL_IF" ]; then
    echo "Error: SLIP interface was not created. Check dmesg."
    exit 1
fi

echo "Configuring interface $SL_IF (IP 10.0.0.2, Peer 10.0.0.1, MTU 1400, qlen 500)..."
ip link set "$SL_IF" up mtu 1400 txqueuelen 500
ip addr flush dev "$SL_IF"
ip addr add 10.0.0.2 peer 10.0.0.1 dev "$SL_IF"

ip route add 10.0.0.255 dev "$SL_IF" 2>/dev/null || true

echo
echo "======================================================"
echo " ESP32-C3 Network Bridge is UP on interface $SL_IF!"
echo " Local IP:  10.0.0.2"
echo " Remote IP: 10.0.0.1"
echo "======================================================"
ip addr show dev "$SL_IF"
echo
echo "To test connection to S3 (PC 1), run:"
echo "  ping 10.0.0.1"