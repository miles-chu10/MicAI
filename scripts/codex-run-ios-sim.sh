#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SIMULATOR_UDID="${1:-}"
FIXTURE="${2:-primary}"
APP_BUNDLE="$PROJECT_ROOT/dist-ios/MicAIiOS.app"
BUNDLE_ID="com.mileschu.micai.ios"

if [ -z "$SIMULATOR_UDID" ]; then
  echo "Usage: $0 <booted-simulator-udid> [primary|approved|target-unavailable|insertion-uncertain|narrow]" >&2
  exit 64
fi

case "$FIXTURE" in
  primary|approved|target-unavailable|insertion-uncertain|narrow) ;;
  *)
    echo "Unknown fixture: $FIXTURE" >&2
    exit 64
    ;;
esac

if ! xcrun simctl list devices | grep -F "$SIMULATOR_UDID" | grep -Fq "(Booted)"; then
  echo "Simulator must already be booted: $SIMULATOR_UDID" >&2
  exit 69
fi

test -x "$APP_BUNDLE/MicAIiOS"
xcrun simctl install "$SIMULATOR_UDID" "$APP_BUNDLE"
xcrun simctl launch --terminate-running-process \
  "$SIMULATOR_UDID" \
  "$BUNDLE_ID" \
  --fixture "$FIXTURE"
