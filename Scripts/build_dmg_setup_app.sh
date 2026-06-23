#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${PROJECT_DIR}/Distribution"
SCRIPT_PATH="${DIST_DIR}/DMGSetup.applescript"
APP_PATH="${DIST_DIR}/520CAM Setup.app"
GUIDES_DIR="${APP_PATH}/Contents/Resources/guides"

if [[ ! -f "${SCRIPT_PATH}" ]]; then
  echo "ERROR: Missing ${SCRIPT_PATH}"
  exit 1
fi

rm -rf "${APP_PATH}"
/usr/bin/osacompile -o "${APP_PATH}" "${SCRIPT_PATH}"

mkdir -p "${APP_PATH}/Contents/Resources/en.lproj"
cat > "${APP_PATH}/Contents/Resources/en.lproj/InfoPlist.strings" <<'EOF'
CFBundleDisplayName = "Start Here";
CFBundleName = "Start Here";
EOF

mkdir -p "${GUIDES_DIR}"
cp "${DIST_DIR}/guide-en.html" "${GUIDES_DIR}/guide.html"

ICON_SOURCE="${DIST_DIR}/app-icon-source.png"
if [[ -f "${ICON_SOURCE}" ]]; then
  ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "${ICONSET_DIR}"
  for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "${double}" "${double}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "${ICONSET_DIR}" -o "${APP_PATH}/Contents/Resources/applet.icns"
fi

echo "OK: ${APP_PATH}"
