#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-${APP_PATH:-${PROJECT_DIR}/build-artifacts/520CAM.app}}"
DMG_PATH="${2:-${DMG_PATH:-${PROJECT_DIR}/build-artifacts/520CAM.dmg}}"
STAGING_DIR="${PROJECT_DIR}/build-artifacts/dmg-staging"
DIST_DIR="${PROJECT_DIR}/Distribution"
SETUP_APP_PATH="${DIST_DIR}/520CAM Setup.app"
VOL_NAME="520CAM Install"
APP_BUNDLE_NAME="520CAM.app"
SETUP_APP_NAME="520CAM Setup.app"
DMG_TEMP="${DMG_PATH}.temp.dmg"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "ERROR: Missing ${APP_PATH}"
  echo "Usage: ./Scripts/package_dmg.sh [path/520CAM.app] [path/output.dmg]"
  exit 1
fi

echo "==> Generating DMG background"
"${PROJECT_DIR}/.venv-ai/bin/python" "${PROJECT_DIR}/Scripts/generate_dmg_backgrounds.py"

if [[ ! -f "${DIST_DIR}/dmg-background.png" ]]; then
  echo "ERROR: Missing ${DIST_DIR}/dmg-background.png"
  exit 1
fi

echo "==> Building Setup app"
chmod +x "${PROJECT_DIR}/Scripts/build_dmg_setup_app.sh"
"${PROJECT_DIR}/Scripts/build_dmg_setup_app.sh"

rm -rf "${STAGING_DIR}" "${DMG_PATH}" "${DMG_TEMP}"
while IFS= read -r vol; do
  hdiutil detach "${vol}" >/dev/null 2>&1 || true
done < <(mount | sed -n 's/.* on \(.*\) (.*$/\1/p' | grep '^/Volumes/520CAM')

mkdir -p "${STAGING_DIR}"
ditto "${APP_PATH}" "${STAGING_DIR}/${APP_BUNDLE_NAME}"
ditto "${SETUP_APP_PATH}" "${STAGING_DIR}/${SETUP_APP_NAME}"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "==> Creating HFS+ DMG"
hdiutil create \
  -volname "${VOL_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "${DMG_TEMP}"

MOUNT_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "${DMG_TEMP}")"
MOUNT_POINT="$(echo "${MOUNT_OUTPUT}" | grep -o '/Volumes/.*' | head -n 1)"

cleanup() {
  if [[ -n "${MOUNT_POINT:-}" ]] && mount | grep -qF "${MOUNT_POINT}"; then
    hdiutil detach "${MOUNT_POINT}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "==> Copying background image"
mkdir -p "${MOUNT_POINT}/.background"
rm -f "${MOUNT_POINT}/.background/"*
cp "${DIST_DIR}/dmg-background.png" "${MOUNT_POINT}/.background/dmg-background.png"
sips -s format tiff "${DIST_DIR}/dmg-background.png" --out "${MOUNT_POINT}/.background/dmg-background.tiff" >/dev/null
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a V "${MOUNT_POINT}/.background" || true
fi

echo "==> Configuring Finder window"
BG_TIFF="${MOUNT_POINT}/.background/dmg-background.tiff"
/usr/bin/osascript <<EOF
tell application "Finder"
  activate
  tell disk "${VOL_NAME}"
    open
    delay 2
    set win to container window
    set current view of win to icon view
    set toolbar visible of win to false
    set statusbar visible of win to false
    set the bounds of win to {200, 120, 800, 520}
    set opts to icon view options of win
    set arrangement of opts to not arranged
    set icon size of opts to 88
    set text size of opts to 12
    set bgFile to POSIX file "${BG_TIFF}" as alias
    set background picture of opts to bgFile
    set position of item "${SETUP_APP_NAME}" of win to {68, 248}
    set position of item "${APP_BUNDLE_NAME}" of win to {248, 248}
    set position of item "Applications" of win to {428, 248}
    close
    delay 2
    open
    update without registering applications
    delay 5
  end tell
end tell
EOF

if [[ ! -f "${MOUNT_POINT}/.DS_Store" ]]; then
  echo "ERROR: Finder did not write .DS_Store to the DMG volume"
  exit 1
fi

sync
sleep 2

echo "==> Compressing final DMG"
hdiutil detach "${MOUNT_POINT}"
MOUNT_POINT=""
rm -f "${DMG_PATH}"
hdiutil convert "${DMG_TEMP}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}"
rm -f "${DMG_TEMP}"

VERIFY_MOUNT="$(hdiutil attach "${DMG_PATH}" -nobrowse | grep -o '/Volumes/.*' | head -n 1)"
if [[ ! -f "${VERIFY_MOUNT}/.DS_Store" ]]; then
  hdiutil detach "${VERIFY_MOUNT}" >/dev/null 2>&1 || true
  echo "ERROR: Final DMG is missing .DS_Store"
  exit 1
fi
hdiutil detach "${VERIFY_MOUNT}" >/dev/null 2>&1 || true

echo "OK: DMG ready at ${DMG_PATH}"
