#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/Library/CoreMediaIO/Plug-Ins/DAL"
PLUGIN="$INSTALL_DIR/VirtualFaceCamDALPlugin.plugin"

echo "==> Removing $PLUGIN"
sudo rm -rf "$PLUGIN"

echo "==> Restarting camera services"
sudo killall -9 VDCAssistant || true
sudo killall -9 AppleCameraAssistant || true

echo "Plugin removido."
