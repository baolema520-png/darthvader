#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$PROJECT_DIR/VirtualFaceCam.xcodeproj"
SCHEME="VirtualFaceCamDALPlugin"
CONFIGURATION="${1:-Release}"
DESTINATION="platform=macOS"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-Z2Y4VR3J34}"
CODE_SIGN_IDENTITY_VALUE="${CODE_SIGN_IDENTITY_VALUE:-ECD73ED350EB1ECABF48534E59753F8123F1085A}"

echo "==> Building DAL plugin ($CONFIGURATION)"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  build >/tmp/virtualfacecam_dal_build.log

BUILD_SETTINGS=$(xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -showBuildSettings 2>/dev/null)

BUILT_PRODUCTS_DIR=$(awk -F' = ' '/ BUILT_PRODUCTS_DIR = / {print $2; exit}' <<<"$BUILD_SETTINGS")
FULL_PRODUCT_NAME=$(awk -F' = ' '/ FULL_PRODUCT_NAME = / {print $2; exit}' <<<"$BUILD_SETTINGS")
PLUGIN_PATH="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"

if [[ -z "${PLUGIN_PATH:-}" || ! -d "$PLUGIN_PATH" ]]; then
  echo "No se encontro plugin compilado automaticamente. Revisa /tmp/virtualfacecam_dal_build.log"
  exit 1
fi

echo "==> Signing plugin with identity: $CODE_SIGN_IDENTITY_VALUE"
codesign --force --deep --timestamp=none --sign "$CODE_SIGN_IDENTITY_VALUE" "$PLUGIN_PATH"
codesign -dv --verbose=2 "$PLUGIN_PATH" >/tmp/virtualfacecam_dal_codesign.log 2>&1 || true

INSTALL_DIR="/Library/CoreMediaIO/Plug-Ins/DAL"
PLUGIN_NAME="VirtualFaceCamDALPlugin.plugin"
TARGET_PLUGIN_PATH="$INSTALL_DIR/$PLUGIN_NAME"

echo "==> Requesting admin permissions (sudo)"
sudo -v

echo "==> Installing to $INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR"
sudo rm -rf "$TARGET_PLUGIN_PATH"
sudo cp -R "$PLUGIN_PATH" "$INSTALL_DIR/"
sudo chown -R root:wheel "$TARGET_PLUGIN_PATH"
sudo chmod -R 755 "$TARGET_PLUGIN_PATH"

echo "==> Restarting camera services"
sudo killall -9 VDCAssistant || true
sudo killall -9 AppleCameraAssistant || true

echo "==> Installed:"
ls -la "$TARGET_PLUGIN_PATH"
echo "Listo. Reinicia Zoom/Teams/Chrome y revisa selector de camara."
