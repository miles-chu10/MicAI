#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
INSTALL_ROOT="${MICAI_INSTALL_DIR:-/Applications}"
TARGET_APP="$INSTALL_ROOT/MicAI.app"

bash "$PROJECT_ROOT/scripts/codex-install.sh"
exec /usr/bin/open "$TARGET_APP"
