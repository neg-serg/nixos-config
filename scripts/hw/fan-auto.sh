#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "Restarting fancontrol service..."
if systemctl restart fancontrol; then
    echo "Automatic fan control restored."
else
    echo "Error: Failed to restart fancontrol service."
    exit 1
fi
