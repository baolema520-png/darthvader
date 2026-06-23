#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${PROJECT_DIR}/build-artifacts/520CAM.app"
ZIP_PATH="${PROJECT_DIR}/build-artifacts/520CAM.zip"

APPLE_ID="${APPLE_ID:-}"
TEAM_ID="${TEAM_ID:-}"
APP_PASSWORD="${APP_PASSWORD:-}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "ERROR: Falta ${APP_PATH}. Ejecuta primero ./Scripts/build_release_app.sh"
  exit 1
fi

if [[ -z "${APPLE_ID}" || -z "${TEAM_ID}" || -z "${APP_PASSWORD}" ]]; then
  cat <<EOF
ERROR: faltan credenciales de notarizacion.
Define variables de entorno:
  APPLE_ID="tu_apple_id@icloud.com"
  TEAM_ID="TU_TEAM_ID"
  APP_PASSWORD="app-specific-password"
EOF
  exit 1
fi

echo "==> Regenerando ZIP para notarytool"
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo "==> Enviando a notarizacion"
xcrun notarytool submit "${ZIP_PATH}" \
  --apple-id "${APPLE_ID}" \
  --team-id "${TEAM_ID}" \
  --password "${APP_PASSWORD}" \
  --wait

echo "==> Aplicando staple a la app"
xcrun stapler staple "${APP_PATH}"

echo "==> Verificando ticket stapled"
spctl -a -vv "${APP_PATH}"

echo "OK: app notarizada y stapled."
