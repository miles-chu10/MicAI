#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
INSTALL_ROOT="${MICAI_INSTALL_DIR:-/Applications}"
TARGET_APP="$INSTALL_ROOT/MicAI.app"
TARGET_BUNDLE_ID="com.mileschu.micai"

if [[ "$INSTALL_ROOT" != /* ]] || [ "$INSTALL_ROOT" = "/" ]; then
  echo "MICAI_INSTALL_DIR must be an absolute directory other than /." >&2
  exit 1
fi

bash "$PROJECT_ROOT/scripts/codex-build.sh"
mkdir -p "$INSTALL_ROOT"

if /usr/bin/pgrep -qx MicAI; then
  /usr/bin/osascript -e "tell application id \"$TARGET_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! /usr/bin/pgrep -qx MicAI; then
      break
    fi
    sleep 0.25
  done
  if /usr/bin/pgrep -qx MicAI; then
    echo "MicAI is still running; quit it before installing." >&2
    exit 1
  fi
fi

if [ -e "$TARGET_APP" ]; then
  case "$TARGET_APP" in
    "$INSTALL_ROOT/MicAI.app")
      find "$TARGET_APP" -depth -delete
      ;;
    *)
      echo "Refusing to replace unexpected app path: $TARGET_APP" >&2
      exit 1
      ;;
  esac
fi

/usr/bin/ditto "$PROJECT_ROOT/dist/MicAI.app" "$TARGET_APP"
/usr/bin/codesign --verify --deep --strict "$TARGET_APP"
echo "Installed $TARGET_APP"
