#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-Release}"

"$PROJECT_DIR/Scripts/install_dal_plugin.sh" "$CONFIGURATION"
"$PROJECT_DIR/Scripts/validate_dal_install.sh"

echo "==> DAL plugin instalado y validado."
