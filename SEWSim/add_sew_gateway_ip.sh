#!/usr/bin/env bash
set -euo pipefail

SEW_IP="${1:-10.150.2.4/24}"
INTERFACE="${2:-eth0}"

echo "[SEW] Adding ${SEW_IP} to ${INTERFACE}"
sudo ip addr add "${SEW_IP}" dev "${INTERFACE}" || true
sudo ip addr show dev "${INTERFACE}"

echo "[SEW] Done. To persist across reboot, add this to dhcpcd.conf or systemd-networkd config."
