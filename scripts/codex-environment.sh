#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
export PROJECT_ROOT

# shellcheck source=scripts/codex-swift-env.sh
source "$SCRIPT_DIR/codex-swift-env.sh"

command_name="${1:-check}"
case "$command_name" in
  check)
    printf 'Project: %s\n' "$PROJECT_ROOT"
    printf 'Swift: %s\n' "$MICAI_SWIFT_BIN"
    "$MICAI_SWIFT_BIN" --version | sed -n '1p'
    printf 'SDKROOT: %s\n' "$MICAI_SDKROOT"
    printf 'Module cache: %s\n' "$CLANG_MODULE_CACHE_PATH"
    printf 'Swift scratch: %s\n' "$MICAI_SWIFT_SCRATCH_PATH"
    ;;
  setup)
    cd "$PROJECT_ROOT"
    "$MICAI_SWIFT_BIN" package --scratch-path "$MICAI_SWIFT_SCRATCH_PATH" resolve
    exec bash "$SCRIPT_DIR/codex-typecheck.sh"
    ;;
  build | run | test | lint | typecheck)
    exec bash "$SCRIPT_DIR/codex-${command_name}.sh" "${@:2}"
    ;;
  *)
    echo "Usage: $0 {check|setup|build|run|test|lint|typecheck}" >&2
    exit 2
    ;;
esac
