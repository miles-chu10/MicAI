#!/bin/bash

# Resolve a Swift/SDK pair once per command so local and worktree shells use the
# same compatible toolchain without depending on interactive shell shims.

micai_swift_is_compatible() {
  local candidate="$1"
  local version

  [ -x "$candidate" ] || return 1
  version="$("$candidate" --version 2>/dev/null)" || return 1
  [[ "$version" =~ Swift\ version\ ([6-9]|[1-9][0-9]+)\. ]]
}

if [ -n "${MICAI_SWIFT_BIN:-}" ]; then
  if ! micai_swift_is_compatible "$MICAI_SWIFT_BIN"; then
    echo "MICAI_SWIFT_BIN must name an executable Swift 6+ toolchain." >&2
    return 1 2>/dev/null || exit 1
  fi
else
  MICAI_ACTIVE_SWIFT="$(command -v swift 2>/dev/null || true)"
  MICAI_SWIFT_633_BIN="${HOME}/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain/usr/bin/swift"
  for MICAI_SWIFT_CANDIDATE in /usr/bin/swift "$MICAI_ACTIVE_SWIFT" "$MICAI_SWIFT_633_BIN"; do
    if micai_swift_is_compatible "$MICAI_SWIFT_CANDIDATE"; then
      MICAI_SWIFT_BIN="$MICAI_SWIFT_CANDIDATE"
      break
    fi
  done
  unset MICAI_ACTIVE_SWIFT MICAI_SWIFT_633_BIN MICAI_SWIFT_CANDIDATE
fi

if [ -z "${MICAI_SWIFT_BIN:-}" ]; then
  echo "MicAI requires Swift 6 or newer; no compatible toolchain was found." >&2
  return 1 2>/dev/null || exit 1
fi

MICAI_SWIFT_TOOLCHAIN_DIR="$(cd "$(dirname "$MICAI_SWIFT_BIN")" && pwd -P)"
MICAI_SWIFTC_BIN="$MICAI_SWIFT_TOOLCHAIN_DIR/swiftc"
if [ ! -x "$MICAI_SWIFTC_BIN" ]; then
  echo "The selected Swift toolchain has no executable swiftc sibling." >&2
  return 1 2>/dev/null || exit 1
fi

MICAI_SWIFT_VERSION="$("$MICAI_SWIFT_BIN" --version 2>/dev/null)"
if [ -n "${MICAI_SDKROOT:-}" ]; then
  if [ ! -d "$MICAI_SDKROOT" ]; then
    echo "MICAI_SDKROOT must name an existing macOS SDK directory." >&2
    return 1 2>/dev/null || exit 1
  fi
  SDKROOT="$MICAI_SDKROOT"
elif [ -z "${SDKROOT:-}" ]; then
  MICAI_SELECTED_DEVELOPER_DIR="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
  MICAI_CLT_COMPATIBLE_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
  if [ "$MICAI_SELECTED_DEVELOPER_DIR" = /Library/Developer/CommandLineTools ] &&
    [[ "$MICAI_SWIFT_VERSION" == *"Swift version 6.3"* ||
      "$MICAI_SWIFT_VERSION" == *"Swift version 6.4"* ]] &&
    [ -d "$MICAI_CLT_COMPATIBLE_SDK" ]; then
    # The macOS 27 CLT SDK exposes SwiftUI.State as a macro but does not ship
    # SwiftUIMacros. The 26.5 SDK is the newest installed CLT SDK that remains
    # self-contained for this SwiftPM-only app.
    SDKROOT="$MICAI_CLT_COMPATIBLE_SDK"
  else
    SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  fi
  unset MICAI_SELECTED_DEVELOPER_DIR MICAI_CLT_COMPATIBLE_SDK
fi

if [ -z "${SDKROOT:-}" ] || [ ! -d "$SDKROOT" ]; then
  echo "No compatible macOS SDK was found for the selected Swift toolchain." >&2
  return 1 2>/dev/null || exit 1
fi

MICAI_SDKROOT="$SDKROOT"
PATH="$MICAI_SWIFT_TOOLCHAIN_DIR:$PATH"
export MICAI_SWIFT_BIN MICAI_SWIFTC_BIN MICAI_SDKROOT SDKROOT PATH

if [ -n "${PROJECT_ROOT:-}" ]; then
  MICAI_SWIFT_CACHE_TAG="$(printf '%s\n' "$MICAI_SWIFT_VERSION" | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/swift-\1/p' | sed -n '1p')"
  MICAI_SDK_CACHE_TAG="$(basename "$SDKROOT" | tr -cd '[:alnum:]._-')"
  MICAI_PROJECT_CACHE_TAG="$(printf '%s' "$PROJECT_ROOT" | shasum -a 256 | awk '{print substr($1, 1, 12)}')"
  MICAI_CACHE_USER_ID="${UID:-$(id -u)}"
  MICAI_MODULE_CACHE_PATH="${MICAI_MODULE_CACHE_PATH:-$PROJECT_ROOT/.build/module-cache-$MICAI_SWIFT_CACHE_TAG-$MICAI_SDK_CACHE_TAG}"
  MICAI_SWIFT_SCRATCH_PATH="${MICAI_SWIFT_SCRATCH_PATH:-/private/tmp/micai-swift-$MICAI_CACHE_USER_ID-$MICAI_PROJECT_CACHE_TAG-$MICAI_SWIFT_CACHE_TAG-$MICAI_SDK_CACHE_TAG}"
  if [[ "$MICAI_SWIFT_SCRATCH_PATH" != /* ]] || [ "$MICAI_SWIFT_SCRATCH_PATH" = "/" ]; then
    echo "MICAI_SWIFT_SCRATCH_PATH must be an absolute directory other than /." >&2
    return 1 2>/dev/null || exit 1
  fi
  mkdir -p "$MICAI_MODULE_CACHE_PATH" "$MICAI_SWIFT_SCRATCH_PATH"
  export CLANG_MODULE_CACHE_PATH="$MICAI_MODULE_CACHE_PATH"
  export SWIFTPM_MODULECACHE_OVERRIDE="$MICAI_MODULE_CACHE_PATH"
  export MICAI_SWIFT_SCRATCH_PATH
  unset MICAI_SWIFT_CACHE_TAG MICAI_SDK_CACHE_TAG MICAI_PROJECT_CACHE_TAG MICAI_CACHE_USER_ID
fi

unset MICAI_SWIFT_TOOLCHAIN_DIR MICAI_SWIFT_VERSION
