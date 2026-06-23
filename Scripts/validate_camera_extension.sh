#!/usr/bin/env bash
set -euo pipefail

EXT_ID="com.virtualfacecam.app.cameraextension"

echo "==> Verificando extension del sistema: ${EXT_ID}"
if systemextensionsctl list | awk -v id="${EXT_ID}" 'BEGIN{IGNORECASE=1} index($0, id){found=1} END{exit(found?0:1)}'; then
  echo "OK: Extension registrada en systemextensionsctl."
  systemextensionsctl list | awk -v id="${EXT_ID}" 'BEGIN{IGNORECASE=1} index($0, id){print NR ":" $0}'
else
  echo "ERROR: Extension no registrada aun."
  echo "Abre la app, pulsa 'Activate Camera Extension' y aprueba en Privacidad y seguridad."
  exit 1
fi

echo
echo "==> Listando camaras visibles por AVFoundation (incluye virtuales si ya estan publicadas)"
swift - <<'SWIFT'
import AVFoundation

let discovery = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
    mediaType: .video,
    position: .unspecified
)

print("Dispositivos de video detectados: \(discovery.devices.count)")
for d in discovery.devices {
    print("- \(d.localizedName) [\(d.uniqueID)]")
}
SWIFT

echo
echo "Si ves '520CAM', ya deberia aparecer en Zoom/Meet/Teams (reinicia la app de videollamada si estaba abierta)."
