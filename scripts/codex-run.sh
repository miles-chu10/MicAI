#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

bash "$PROJECT_ROOT/scripts/codex-build.sh"
exec /usr/bin/open "$PROJECT_ROOT/dist/MicAI.app"
