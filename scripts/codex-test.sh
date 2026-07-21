#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

if [ -n "${MICAI_SDKROOT:-}" ]; then
  export SDKROOT="$MICAI_SDKROOT"
elif [ -z "${SDKROOT:-}" ]; then
  SWIFT_VERSION="$(swift --version)"
  COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
  if [[ "$SWIFT_VERSION" == *"Swift version 6.3."* ]] && [ -d "$COMPATIBLE_SDK" ]; then
    export SDKROOT="$COMPATIBLE_SDK"
  fi
fi

cd "$PROJECT_ROOT"
exec swift test "$@"
