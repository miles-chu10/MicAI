#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
LOCAL_DEV_ENV="${CODEX_LOCAL_DEV_ENV:-$PROJECT_ROOT/../.codex/scripts/local-dev-env.sh}"

if [ ! -f "$LOCAL_DEV_ENV" ]; then
  echo "Error: local dev helper not found: $LOCAL_DEV_ENV" >&2
  exit 1
fi

exec bash "$LOCAL_DEV_ENV" "lint" "$PROJECT_ROOT"
