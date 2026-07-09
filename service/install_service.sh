#!/usr/bin/env bash
set -euo pipefail

TARGET_SERVICE="/etc/systemd/system/sew-sim.service"
SRC_SERVICE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sew-sim.service"

echo "[SEW] Installing systemd service to ${TARGET_SERVICE}"
sudo cp "${SRC_SERVICE}" "${TARGET_SERVICE}"
sudo systemctl daemon-reload
sudo systemctl enable sew-sim.service

echo "[SEW] Service enabled. Use commands:"
echo "  sudo systemctl start sew-sim"
echo "  sudo systemctl status sew-sim"
echo "  sudo journalctl -u sew-sim -f"
