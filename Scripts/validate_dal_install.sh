#!/usr/bin/env bash
set -euo pipefail

PLUGIN="/Library/CoreMediaIO/Plug-Ins/DAL/VirtualFaceCamDALPlugin.plugin"

if [[ ! -d "$PLUGIN" ]]; then
  echo "Plugin no instalado en $PLUGIN"
  exit 1
fi

echo "==> Plugin presente"
ls -la "$PLUGIN"

echo "==> Bundle identifier"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLUGIN/Contents/Info.plist"

echo "==> Factory metadata"
/usr/libexec/PlistBuddy -c "Print :CFPlugInFactories" "$PLUGIN/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFPlugInTypes" "$PLUGIN/Contents/Info.plist"

echo "==> Signature"
codesign -dv --verbose=4 "$PLUGIN" 2>&1 | sed -n '1,8p'
echo "==> Gatekeeper assessment"
spctl -a -t execute -vv "$PLUGIN" || true

echo "Validacion basica completada."
