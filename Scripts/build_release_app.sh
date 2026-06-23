#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_DIR}/VirtualFaceCam.xcodeproj"
SCHEME="${SCHEME:-VirtualFaceCamApp}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_PATH="${PROJECT_DIR}/build-artifacts/520CAM.xcarchive"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/520CAM.app"
OUT_APP_PATH="${PROJECT_DIR}/build-artifacts/520CAM.app"
OUT_ZIP_PATH="${PROJECT_DIR}/build-artifacts/520CAM.zip"

mkdir -p "${PROJECT_DIR}/build-artifacts"
rm -rf "${ARCHIVE_PATH}" "${OUT_APP_PATH}" "${OUT_ZIP_PATH}"

echo "==> Archivando ${SCHEME} (${CONFIGURATION})"
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -archivePath "${ARCHIVE_PATH}" \
  archive

if [[ ! -d "${APP_PATH}" ]]; then
  echo "ERROR: No se encontro app archivada en ${APP_PATH}"
  exit 1
fi

echo "==> Copiando app release a build-artifacts"
ditto "${APP_PATH}" "${OUT_APP_PATH}"

echo "==> Validando firma"
codesign --verify --deep --strict --verbose=2 "${OUT_APP_PATH}"

echo "==> Empaquetando ZIP para notarizacion"
ditto -c -k --sequesterRsrc --keepParent "${OUT_APP_PATH}" "${OUT_ZIP_PATH}"

echo "OK: build release listo"
echo "- App: ${OUT_APP_PATH}"
echo "- Zip: ${OUT_ZIP_PATH}"
