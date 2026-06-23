#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${PROJECT_DIR}/build-artifacts/520CAM.app"
EXT_ID="com.virtualfacecam.app.cameraextension"

echo "==> Prepublish checks"
echo

if [[ ! -d "${APP_PATH}" ]]; then
  echo "ERROR: No existe ${APP_PATH}"
  echo "Ejecuta primero ./Scripts/build_release_app.sh"
  exit 1
fi

echo "1) Firma de app"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
echo

echo "2) Gatekeeper / spctl"
spctl -a -vv "${APP_PATH}" || true
echo

echo "3) Entitlements de app"
codesign -d --entitlements :- "${APP_PATH}" >/dev/null
echo "OK: entitlements de app legibles."
echo

echo "4) Estado extension CMIO registrada"
systemextensionsctl list com.apple.system_extension.cmio | awk -v id="${EXT_ID}" 'BEGIN{IGNORECASE=1} index($0, id){print}'
echo

echo "5) Enumeracion de camaras via AVFoundation"
swift - <<'SWIFT'
import AVFoundation

let discovery = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
    mediaType: .video,
    position: .unspecified
)
print("Dispositivos encontrados: \(discovery.devices.count)")
for d in discovery.devices {
    print("- \(d.localizedName) [\(d.uniqueID)]")
}
SWIFT
echo
echo "OK: checks completados."
