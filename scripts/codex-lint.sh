#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
export PROJECT_ROOT

# shellcheck source=scripts/codex-swift-env.sh
source "$SCRIPT_DIR/codex-swift-env.sh"

cd "$PROJECT_ROOT"
exec "$MICAI_SWIFT_BIN" format lint --recursive --strict Package.swift Sources Tests
