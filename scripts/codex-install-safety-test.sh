#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
INSTALL_SCRIPT="$SCRIPT_DIR/codex-install.sh"
SOURCE_APP="$PROJECT_ROOT/dist/MicAI.app"
ACTIVE_APPLY_PID=""
ACTIVE_SECONDARY_PID=""
ACTIVE_HOOK_RELEASE=""
ACTIVE_APPLY_STATUS=""
SUITE_MODE="${1:-all}"

case "$SUITE_MODE" in
  all | --targeted-fifth-review | --targeted-transaction-regression | --targeted-review-six | --targeted-review-seven | --targeted-review-eight | --targeted-review-eleven)
    ;;
  *)
    echo "Usage: bash scripts/codex-install-safety-test.sh [--targeted-fifth-review | --targeted-transaction-regression | --targeted-review-six | --targeted-review-seven | --targeted-review-eight | --targeted-review-eleven]" >&2
    exit 2
    ;;
esac

path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

sha256_file() {
  /usr/bin/shasum -a 256 <"$1" | /usr/bin/awk '{print $1}'
}

fail() {
  echo "Install safety test failed: $1" >&2
  exit 1
}

cleanup_active_apply() {
  local status=$?
  trap - EXIT INT TERM

  if [ -n "$ACTIVE_APPLY_PID" ]; then
    if [ -n "$ACTIVE_HOOK_RELEASE" ] && ! path_exists "$ACTIVE_HOOK_RELEASE"; then
      /bin/mkdir "$ACTIVE_HOOK_RELEASE" 2>/dev/null || true
    fi
    /bin/kill -CONT "$ACTIVE_APPLY_PID" 2>/dev/null || true
    /bin/kill -TERM "$ACTIVE_APPLY_PID" 2>/dev/null || true
    set +e
    wait "$ACTIVE_APPLY_PID" 2>/dev/null
    set -e
  fi
  if [ -n "$ACTIVE_SECONDARY_PID" ]; then
    /bin/kill -CONT "$ACTIVE_SECONDARY_PID" 2>/dev/null || true
    /bin/kill -TERM "$ACTIVE_SECONDARY_PID" 2>/dev/null || true
    set +e
    wait "$ACTIVE_SECONDARY_PID" 2>/dev/null
    set -e
  fi
  exit "$status"
}

trap cleanup_active_apply EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [ "$expected" != "$actual" ]; then
    fail "$label (expected '$expected', found '$actual')"
  fi
}

assert_output_contains() {
  local output_file="$1"
  local expected="$2"
  local output

  output="$(/bin/cat "$output_file")"
  case "$output" in
    *"$expected"*)
      ;;
    *)
      fail "missing output '$expected' in $output_file"
      ;;
  esac
}

assert_output_not_contains() {
  local output_file="$1"
  local unexpected="$2"
  local output

  output="$(/bin/cat "$output_file")"
  case "$output" in
    *"$unexpected"*)
      fail "unexpected output '$unexpected' in $output_file"
      ;;
  esac
}

new_fixture() {
  local name="$1"
  local fixture

  fixture="$(/usr/bin/mktemp -d "/private/tmp/micai-install-$name.XXXXXX")"
  /bin/mkdir "$fixture/Applications"
  /bin/mkdir "$fixture/hooks"
  echo "$fixture"
}

remove_exact_fixture_root() {
  local fixture="$1"
  local parent
  local name

  parent="$(/usr/bin/dirname "$fixture")"
  name="$(/usr/bin/basename "$fixture")"
  if [ "$parent" != "/private/tmp" ] \
    || [[ ! "$name" == micai-install-*.?????? ]] \
    || [ ! -d "$fixture" ] \
    || [ -L "$fixture" ]; then
    fail "refusing to clean an unverified fixture root: $fixture"
  fi
  /bin/rm -rf -- "$fixture"
  if path_exists "$fixture"; then
    fail "verified fixture root remained after harness cleanup: $fixture"
  fi
}

start_hooked_apply() {
  local fixture="$1"
  local command="$2"
  local point="$3"
  local output="$4"

  ACTIVE_HOOK_RELEASE="$fixture/hooks/$point.release"
  MICAI_INSTALL_TEST_HOOK_POINT="$point" \
    MICAI_INSTALL_TEST_HOOK_DIR="$fixture/hooks" \
    /bin/bash -c "$command" >"$output" 2>&1 &
  ACTIVE_APPLY_PID=$!
}

wait_for_hook() {
  local fixture="$1"
  local point="$2"
  local ready="$fixture/hooks/$point.ready"
  local attempts=0

  while [ "$attempts" -lt 1000 ]; do
    attempts=$((attempts + 1))
    if [ -d "$ready" ] && [ ! -L "$ready" ]; then
      return 0
    fi
    if ! /bin/kill -0 "$ACTIVE_APPLY_PID" 2>/dev/null; then
      fail "hooked apply exited before reaching $point"
    fi
    /bin/sleep 0.01
  done
  fail "timed out waiting for deterministic installer hook $point"
}

release_hook() {
  if path_exists "$ACTIVE_HOOK_RELEASE"; then
    fail "hook release marker is already occupied: $ACTIVE_HOOK_RELEASE"
  fi
  /bin/mkdir "$ACTIVE_HOOK_RELEASE"
}

finish_hooked_apply() {
  set +e
  wait "$ACTIVE_APPLY_PID"
  ACTIVE_APPLY_STATUS=$?
  set -e
  ACTIVE_APPLY_PID=""
  ACTIVE_HOOK_RELEASE=""
}

make_stale_target() {
  local fixture="$1"
  local target="$fixture/Applications/MicAI.app"

  /usr/bin/ditto "$SOURCE_APP" "$target"
  /bin/mv \
    "$target/Contents/Resources/MicAI.icns" \
    "$fixture/reviewed-original-icon.icns"
  /usr/bin/plutil -remove CFBundleIconFile "$target/Contents/Info.plist"
  /usr/bin/codesign --force --deep --sign - "$target" >/dev/null
  /usr/bin/codesign --verify --deep --strict "$target"
  capture_stale_target_manifest "$fixture"
}

target_manifest_sha256() {
  local target="$1"
  local parent
  local basename
  local state

  parent="$(/usr/bin/dirname "$target")"
  basename="$(/usr/bin/basename "$target")"
  state="$(
    cd "$parent"
    MICAI_INSTALL_DIR="$parent" \
      MICAI_INTERNAL_STATE_HELPER=1 \
      MICAI_INTERNAL_BUNDLE_BASENAME="$basename" \
      MICAI_INTERNAL_METADATA_POLICY=preserve \
      /bin/bash "$INSTALL_SCRIPT" --internal-bundle-state
  )"
  case "$state" in
    [0-9a-f][0-9a-f]*'|'valid | [0-9a-f][0-9a-f]*'|'missing-or-invalid)
      ;;
    *)
      fail "production bundle-state helper returned malformed target state"
      ;;
  esac
  printf '%s\n' "${state%%|*}"
}

capture_stale_target_manifest() {
  local fixture="$1"
  local target="$fixture/Applications/MicAI.app"

  target_manifest_sha256 "$target" >"$fixture/reviewed-target.manifest"
}

verify_target_manifest() {
  local fixture="$1"
  local target="$2"
  local expected_manifest

  expected_manifest="$(/bin/cat "$fixture/reviewed-target.manifest")"
  assert_equal "$expected_manifest" "$(target_manifest_sha256 "$target")" \
    "reviewed target full manifest"
}

write_plan() {
  local fixture="$1"
  local output="$2"

  MICAI_INSTALL_DIR="$fixture/Applications" \
    /bin/bash "$INSTALL_SCRIPT" --plan >"$output"
}

plan_value() {
  local plan="$1"
  local label="$2"

  /usr/bin/sed -n "s|^  $label: ||p" "$plan"
}

plan_apply_command() {
  /usr/bin/python3 - "$1" <<'PY'
import sys

plan_path = sys.argv[1]
with open(plan_path, "rb") as plan_file:
    plan = plan_file.read()

heading = plan.find(b"Exact apply operation ")
if heading < 0:
    sys.exit(0)
start_marker = b"\n  MICAI_INSTALL_DIR="
start = plan.find(start_marker, heading)
if start < 0:
    sys.exit(0)
start += len(b"\n  ")
end = plan.find(b"\n\nThe apply path does not rebuild", start)
if end < 0:
    sys.exit(1)
sys.stdout.buffer.write(plan[start:end])
PY
}

verify_stale_target() {
  local fixture="$1"
  local expected_inode="$2"
  local expected_executable_hash="$3"
  local expected_plist_hash="$4"
  local target="$fixture/Applications/MicAI.app"

  verify_target_manifest "$fixture" "$target"
  assert_equal "$expected_inode" "$(/usr/bin/stat -f '%i' "$target")" \
    "reviewed target inode"
  assert_equal "$expected_executable_hash" \
    "$(sha256_file "$target/Contents/MacOS/MicAI")" \
    "reviewed target executable hash"
  assert_equal "$expected_plist_hash" \
    "$(sha256_file "$target/Contents/Info.plist")" \
    "reviewed target plist hash"
  if path_exists "$target/Contents/Resources/MicAI.icns"; then
    fail "reviewed target icon unexpectedly exists"
  fi
  /usr/bin/codesign --verify --deep --strict "$target"
}

test_stale_target_verifier_full_manifest() {
  local fixture
  local target
  local metadata_file
  local original_mode
  local original_inode
  local original_executable_hash
  local original_plist_hash
  local status

  fixture="$(new_fixture stale-verifier-manifest)"
  make_stale_target "$fixture"
  target="$fixture/Applications/MicAI.app"
  metadata_file="$target/Contents/_CodeSignature/CodeResources"
  original_mode="$(/usr/bin/stat -f '%Lp' "$metadata_file")"
  original_inode="$(/usr/bin/stat -f '%i' "$target")"
  original_executable_hash="$(sha256_file "$target/Contents/MacOS/MicAI")"
  original_plist_hash="$(sha256_file "$target/Contents/Info.plist")"

  printf 'unasserted fixture entry\n' \
    >"$target/Contents/Resources/unasserted-entry.txt"
  set +e
  (
    verify_stale_target \
      "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  ) >"$fixture/unasserted-entry.out" 2>&1
  status=$?
  set -e
  [ "$status" -ne 0 ] \
    || fail "stale-target verifier accepted an unasserted bundle entry"
  assert_output_contains "$fixture/unasserted-entry.out" \
    "reviewed target full manifest"
  /bin/rm "$target/Contents/Resources/unasserted-entry.txt"

  /bin/chmod 600 "$metadata_file"
  set +e
  (
    verify_stale_target \
      "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  ) >"$fixture/metadata.out" 2>&1
  status=$?
  set -e
  [ "$status" -ne 0 ] \
    || fail "stale-target verifier accepted an unasserted metadata mutation"
  assert_output_contains "$fixture/metadata.out" \
    "reviewed target full manifest"
  /bin/chmod "$original_mode" "$metadata_file"

  verify_stale_target \
    "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  echo "PASS stale-target verifier rejects unasserted entries and metadata mutations: $fixture"
}

test_dangling_staged_symlink() {
  local fixture
  local plan
  local command
  local staged
  local redirect_root
  local redirected_app
  local target
  local original_inode
  local original_executable_hash
  local original_plist_hash
  local backup_contents
  local status

  fixture="$(new_fixture dangling-stage)"
  make_stale_target "$fixture"
  target="$fixture/Applications/MicAI.app"
  original_inode="$(/usr/bin/stat -f '%i' "$target")"
  original_executable_hash="$(sha256_file "$target/Contents/MacOS/MicAI")"
  original_plist_hash="$(sha256_file "$target/Contents/Info.plist")"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"
  staged="$(plan_value "$plan" "Staged copy")"
  redirect_root="$fixture/redirected-writes"
  redirected_app="$redirect_root/escaped.app"
  /bin/mkdir "$redirect_root"
  /bin/ln -s "$redirected_app" "$staged"

  set +e
  /bin/bash -c "$command" >"$fixture/apply.out" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "dangling staged symlink apply unexpectedly succeeded"
  [ -L "$staged" ] || fail "dangling staged symlink was deleted or replaced"
  if path_exists "$redirected_app"; then
    fail "dangling staged symlink redirected a write"
  fi
  verify_stale_target \
    "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  if path_exists "$fixture/Applications/.MicAI-install.lock"; then
    fail "dangling staged symlink test left the install lock"
  fi
  assert_output_contains "$fixture/apply.out" \
    "Reserved install path is occupied or a symbolic link"
  echo "PASS dangling staged-path symlink: $fixture"
}

test_symlinked_backup_root() {
  local fixture
  local plan
  local command
  local staged
  local backup_root
  local redirect_root
  local target
  local original_inode
  local original_executable_hash
  local original_plist_hash
  local status

  fixture="$(new_fixture symlinked-backup)"
  make_stale_target "$fixture"
  target="$fixture/Applications/MicAI.app"
  original_inode="$(/usr/bin/stat -f '%i' "$target")"
  original_executable_hash="$(sha256_file "$target/Contents/MacOS/MicAI")"
  original_plist_hash="$(sha256_file "$target/Contents/Info.plist")"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"
  staged="$(plan_value "$plan" "Staged copy")"
  backup_root="$fixture/Applications/.MicAI-backups"
  redirect_root="$fixture/redirected-backups"
  /bin/mkdir "$redirect_root"
  /bin/ln -s "$redirect_root" "$backup_root"

  set +e
  /bin/bash -c "$command" >"$fixture/apply.out" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "symlinked backup root apply unexpectedly succeeded"
  [ -L "$backup_root" ] || fail "symlinked backup root was deleted or replaced"
  if path_exists "$staged"; then
    fail "staging began despite a symlinked backup root"
  fi
  if [ -n "$(/usr/bin/find "$redirect_root" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    fail "symlinked backup root redirected a write"
  fi
  verify_stale_target \
    "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  if path_exists "$fixture/Applications/.MicAI-install.lock"; then
    fail "symlinked backup root test left the install lock"
  fi
  assert_output_contains "$fixture/apply.out" \
    "Backup root must not be a symbolic link"
  echo "PASS symlinked backup root: $fixture"
}

test_symlinked_target() {
  local fixture
  local plan
  local command
  local target
  local redirected_target
  local status

  fixture="$(new_fixture symlinked-target)"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"
  target="$fixture/Applications/MicAI.app"
  redirected_target="$fixture/redirected-target.app"
  /bin/ln -s "$redirected_target" "$target"

  set +e
  /bin/bash -c "$command" >"$fixture/apply.out" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "symlinked target apply unexpectedly succeeded"
  [ -L "$target" ] || fail "symlinked target was deleted or replaced"
  if path_exists "$redirected_target"; then
    fail "symlinked target redirected a write"
  fi
  if path_exists "$fixture/Applications/.MicAI-install.lock"; then
    fail "symlinked target test left the install lock"
  fi
  assert_output_contains "$fixture/apply.out" \
    "The installed target changed after acquiring the install lock"
  echo "PASS symlinked target: $fixture"
}

test_trailing_slash_install_root_rejected() {
  local fixture
  local install_root
  local trailing_root
  local install_id="20990101T000000Z"
  local target
  local original_inode
  local original_executable_hash
  local original_plist_hash
  local plan
  local command
  local status

  fixture="$(new_fixture trailing-root)"
  install_root="$fixture/Applications"
  trailing_root="$install_root/"
  make_stale_target "$fixture"
  target="$install_root/MicAI.app"
  original_inode="$(/usr/bin/stat -f '%i' "$target")"
  original_executable_hash="$(sha256_file "$target/Contents/MacOS/MicAI")"
  original_plist_hash="$(sha256_file "$target/Contents/Info.plist")"
  plan="$fixture/trailing-plan.txt"

  set +e
  MICAI_INSTALL_DIR="$trailing_root" MICAI_INSTALL_ID="$install_id" \
    /bin/bash "$INSTALL_SCRIPT" --plan >"$plan" 2>"$fixture/trailing-plan.err"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "trailing-slash plan unexpectedly succeeded"
  [ -z "$(plan_apply_command "$plan")" ] \
    || fail "trailing-slash plan emitted an apply command"
  assert_output_contains "$fixture/trailing-plan.err" \
    "MICAI_INSTALL_DIR must not end with a trailing slash."
  verify_stale_target \
    "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  if path_exists "$install_root/.MicAI-install.lock" \
    || path_exists "$install_root/.MicAI-install-$install_id.app" \
    || path_exists "$install_root/.MicAI-failed-$install_id.app" \
    || path_exists "$install_root/.MicAI-backups"; then
    fail "trailing-slash plan created an install transaction path"
  fi

  set +e
  MICAI_INSTALL_DIR="$trailing_root" MICAI_INSTALL_ID="$install_id" \
    /bin/bash "$INSTALL_SCRIPT" --apply \
      >"$fixture/trailing-apply.out" 2>"$fixture/trailing-apply.err"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "trailing-slash apply unexpectedly succeeded"
  assert_output_contains "$fixture/trailing-apply.err" \
    "MICAI_INSTALL_DIR must not end with a trailing slash."
  verify_stale_target \
    "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  if path_exists "$install_root/.MicAI-install.lock" \
    || path_exists "$install_root/.MicAI-install-$install_id.app" \
    || path_exists "$install_root/.MicAI-failed-$install_id.app" \
    || path_exists "$install_root/.MicAI-backups"; then
    fail "trailing-slash apply created an install transaction path"
  fi

  MICAI_INSTALL_DIR="$install_root" MICAI_INSTALL_ID="$install_id" \
    /bin/bash "$INSTALL_SCRIPT" --plan >"$fixture/canonical-plan.txt"
  command="$(plan_apply_command "$fixture/canonical-plan.txt")"
  [ -n "$command" ] || fail "canonical install root omitted its apply command"
  /bin/bash -c "$command" >"$fixture/canonical-apply.out" 2>&1

  /usr/bin/codesign --verify --deep --strict "$target"
  assert_equal "$(sha256_file "$SOURCE_APP/Contents/Info.plist")" \
    "$(sha256_file "$target/Contents/Info.plist")" \
    "canonical-root target plist hash"
  assert_equal "$(sha256_file "$SOURCE_APP/Contents/Resources/MicAI.icns")" \
    "$(sha256_file "$target/Contents/Resources/MicAI.icns")" \
    "canonical-root target icon hash"
  if path_exists "$install_root/.MicAI-install.lock" \
    || path_exists "$install_root/.MicAI-install-$install_id.app" \
    || path_exists "$install_root/.MicAI-failed-$install_id.app"; then
    fail "canonical-root apply left a transient transaction path"
  fi
  [ -d "$install_root/.MicAI-backups/MicAI-before-$install_id.app" ] \
    || fail "canonical-root apply omitted the recoverable backup"
  echo "PASS trailing-slash roots fail before transaction paths while canonical roots still apply: $fixture"
}

test_hook_scope_rejected() {
  local fixture
  local plan
  local command
  local staged
  local status

  fixture="$(/usr/bin/mktemp -d "/private/tmp/micai-unsafe-hook.XXXXXX")"
  /bin/mkdir "$fixture/Applications" "$fixture/hooks"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"
  staged="$(plan_value "$plan" "Staged copy")"

  set +e
  MICAI_INSTALL_TEST_HOOK_POINT="before-replacement-rename" \
    MICAI_INSTALL_TEST_HOOK_DIR="$fixture/hooks" \
    /bin/bash -c "$command" >"$fixture/apply.out" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "out-of-scope installer test hook unexpectedly succeeded"
  if path_exists "$staged" \
    || path_exists "$fixture/Applications/.MicAI-install.lock" \
    || path_exists "$fixture/Applications/MicAI.app"; then
    fail "out-of-scope installer test hook changed its fixture install root"
  fi
  assert_output_contains "$fixture/apply.out" \
    "Installer test hooks are restricted to an isolated /private/tmp/micai-install-* fixture"
  echo "PASS live-root-ineligible test hook scope: $fixture"
}

test_complete_target_manifest_binding() {
  local fixture
  local plan
  local command
  local target
  local original_inode
  local original_executable_hash
  local original_plist_hash
  local status

  fixture="$(new_fixture target-manifest)"
  make_stale_target "$fixture"
  target="$fixture/Applications/MicAI.app"
  original_inode="$(/usr/bin/stat -f '%i' "$target")"
  original_executable_hash="$(sha256_file "$target/Contents/MacOS/MicAI")"
  original_plist_hash="$(sha256_file "$target/Contents/Info.plist")"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"

  /bin/chmod 600 "$target/Contents/_CodeSignature/CodeResources"
  /usr/bin/codesign --verify --deep --strict "$target"
  capture_stale_target_manifest "$fixture"

  set +e
  /bin/bash -c "$command" >"$fixture/apply.out" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "complete-target-manifest mismatch unexpectedly installed"
  verify_stale_target \
    "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  assert_equal "600" \
    "$(/usr/bin/stat -f '%Lp' "$target/Contents/_CodeSignature/CodeResources")" \
    "target manifest test retained its external mode change"
  if path_exists "$fixture/Applications/.MicAI-install.lock"; then
    fail "target manifest mismatch left the install lock"
  fi
  assert_output_contains "$fixture/apply.out" \
    "The installed target changed after acquiring the install lock"
  echo "PASS complete target manifest binding: $fixture"
}

test_target_metadata_binding() {
  local fixture
  local plan
  local command
  local target
  local metadata_file
  local original_inode
  local original_executable_hash
  local original_plist_hash
  local status
  local flags

  fixture="$(new_fixture target-metadata)"
  make_stale_target "$fixture"
  target="$fixture/Applications/MicAI.app"
  metadata_file="$target/Contents/Info.plist"
  original_inode="$(/usr/bin/stat -f '%i' "$target")"
  original_executable_hash="$(sha256_file "$target/Contents/MacOS/MicAI")"
  original_plist_hash="$(sha256_file "$metadata_file")"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"

  /usr/bin/xattr -w com.micai.install-fixture reviewed-metadata "$metadata_file"
  /bin/chmod +a "everyone allow read" "$metadata_file"
  /usr/bin/chflags hidden "$metadata_file"
  /usr/bin/codesign --verify --deep --strict "$target"
  capture_stale_target_manifest "$fixture"

  set +e
  /bin/bash -c "$command" >"$fixture/apply.out" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "target metadata mismatch unexpectedly installed"
  verify_stale_target \
    "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  assert_equal "reviewed-metadata" \
    "$(/usr/bin/xattr -p com.micai.install-fixture "$metadata_file")" \
    "target metadata test retained its xattr"
  /bin/ls -le "$metadata_file" | /usr/bin/grep -q "everyone allow read" \
    || fail "target metadata test lost its ACL"
  flags="$(/usr/bin/stat -f '%f' "$metadata_file")"
  [ "$flags" -ne 0 ] || fail "target metadata test lost its file flags"
  if path_exists "$fixture/Applications/.MicAI-install.lock"; then
    fail "target metadata mismatch left the install lock"
  fi
  assert_output_contains "$fixture/apply.out" \
    "The installed target changed after acquiring the install lock"
  echo "PASS xattr/ACL/flags target-state binding: $fixture"
}

test_manifest_snapshot_mutation() {
  local fixture
  local plan
  local command
  local target
  local changed_file
  local original_inode
  local original_executable_hash
  local original_plist_hash
  local status

  fixture="$(new_fixture manifest-snapshot-race)"
  make_stale_target "$fixture"
  target="$fixture/Applications/MicAI.app"
  changed_file="$target/Contents/_CodeSignature/CodeResources"
  original_inode="$(/usr/bin/stat -f '%i' "$target")"
  original_executable_hash="$(sha256_file "$target/Contents/MacOS/MicAI")"
  original_plist_hash="$(sha256_file "$target/Contents/Info.plist")"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"

  start_hooked_apply \
    "$fixture" \
    "$command" \
    "inside-target-manifest-between-snapshots" \
    "$fixture/apply.out"
  wait_for_hook "$fixture" "inside-target-manifest-between-snapshots"
  /bin/chmod 600 "$changed_file"
  capture_stale_target_manifest "$fixture"
  release_hook
  finish_hooked_apply
  status="$ACTIVE_APPLY_STATUS"

  [ "$status" -ne 0 ] || fail "mid-snapshot target mutation unexpectedly installed"
  verify_stale_target \
    "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  assert_equal "600" "$(/usr/bin/stat -f '%Lp' "$changed_file")" \
    "mid-snapshot mutation retained its external mode change"
  if path_exists "$fixture/Applications/.MicAI-install.lock"; then
    fail "mid-snapshot target mutation left the install lock"
  fi
  assert_output_contains "$fixture/apply.out" \
    "two complete bundle snapshots did not match"
  echo "PASS deterministic mid-snapshot mutation rejection: $fixture"
}

test_exclusive_backup_destination_directory() {
  local fixture
  local plan
  local command
  local backup
  local target
  local original_inode
  local original_executable_hash
  local original_plist_hash
  local status

  fixture="$(new_fixture backup-directory-race)"
  make_stale_target "$fixture"
  target="$fixture/Applications/MicAI.app"
  original_inode="$(/usr/bin/stat -f '%i' "$target")"
  original_executable_hash="$(sha256_file "$target/Contents/MacOS/MicAI")"
  original_plist_hash="$(sha256_file "$target/Contents/Info.plist")"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"
  backup="$(plan_value "$plan" "Recoverable backup")"

  start_hooked_apply \
    "$fixture" "$command" "before-original-backup-rename" "$fixture/apply.out"
  wait_for_hook "$fixture" "before-original-backup-rename"
  /bin/mkdir "$backup"
  release_hook
  finish_hooked_apply
  status="$ACTIVE_APPLY_STATUS"

  [ "$status" -ne 0 ] || fail "backup destination-directory race unexpectedly succeeded"
  verify_stale_target \
    "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  backup_contents="$(/usr/bin/find "$backup" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)"
  [ -z "$backup_contents" ] \
    || fail "exclusive rename nested the original inside a destination directory"
  if path_exists "$fixture/Applications/.MicAI-install.lock"; then
    fail "backup destination-directory race left the install lock"
  fi
  assert_output_contains "$fixture/apply.out" "State-bound kernel exclusive rename failed"
  echo "PASS exclusive backup destination-directory rejection: $fixture"
}

test_bound_backup_parent_substitution() {
  local fixture
  local plan
  local command
  local backup
  local backup_root
  local displaced_backup_root
  local target
  local original_inode
  local original_executable_hash
  local original_plist_hash
  local status

  fixture="$(new_fixture backup-parent-substitution)"
  make_stale_target "$fixture"
  target="$fixture/Applications/MicAI.app"
  original_inode="$(/usr/bin/stat -f '%i' "$target")"
  original_executable_hash="$(sha256_file "$target/Contents/MacOS/MicAI")"
  original_plist_hash="$(sha256_file "$target/Contents/Info.plist")"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"
  backup="$(plan_value "$plan" "Recoverable backup")"
  backup_root="$(/usr/bin/dirname "$backup")"
  displaced_backup_root="$fixture/displaced-backup-root"

  start_hooked_apply \
    "$fixture" "$command" "before-original-backup-rename" "$fixture/apply.out"
  wait_for_hook "$fixture" "before-original-backup-rename"
  /bin/mv "$backup_root" "$displaced_backup_root"
  /bin/mkdir "$backup_root"
  release_hook
  finish_hooked_apply
  status="$ACTIVE_APPLY_STATUS"

  [ "$status" -ne 0 ] || fail "bound backup-parent substitution unexpectedly succeeded"
  verify_stale_target \
    "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  if [ -n "$(/usr/bin/find "$backup_root" -mindepth 1 -maxdepth 1 -print -quit)" ] \
    || [ -n "$(/usr/bin/find "$displaced_backup_root" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    fail "parent substitution received or nested the reviewed original"
  fi
  if path_exists "$fixture/Applications/.MicAI-install.lock"; then
    fail "bound backup-parent substitution left the install lock"
  fi
  assert_output_contains "$fixture/apply.out" \
    "destination parent changed after topology validation"
  echo "PASS bound backup-parent substitution rejection: $fixture"
}

test_post_kernel_parent_substitution_rollback() {
  local fixture
  local plan
  local command
  local backup
  local staged
  local backup_root
  local displaced_backup_root
  local target
  local lock
  local lock_identity
  local staged_identity
  local original_inode
  local original_executable_hash
  local original_plist_hash
  local status
  local competing_status

  fixture="$(new_fixture post-kernel-parent)"
  make_stale_target "$fixture"
  target="$fixture/Applications/MicAI.app"
  original_inode="$(/usr/bin/stat -f '%i' "$target")"
  original_executable_hash="$(sha256_file "$target/Contents/MacOS/MicAI")"
  original_plist_hash="$(sha256_file "$target/Contents/Info.plist")"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"
  backup="$(plan_value "$plan" "Recoverable backup")"
  staged="$(plan_value "$plan" "Staged copy")"
  backup_root="$(/usr/bin/dirname "$backup")"
  displaced_backup_root="$fixture/displaced-post-kernel-backup-root"
  lock="$fixture/Applications/.MicAI-install.lock"

  start_hooked_apply \
    "$fixture" "$command" "inside-rename-after-kernel" "$fixture/apply.out"
  wait_for_hook "$fixture" "inside-rename-after-kernel"
  path_exists "$backup" \
    || fail "post-kernel hook did not observe the moved original at its destination"
  if path_exists "$target"; then
    fail "post-kernel hook still found the original at its source"
  fi
  /bin/mv "$backup_root" "$displaced_backup_root"
  /bin/mkdir "$backup_root"
  release_hook
  finish_hooked_apply
  status="$ACTIVE_APPLY_STATUS"

  [ "$status" -ne 0 ] || fail "post-kernel parent substitution unexpectedly installed"
  verify_stale_target \
    "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  if [ -n "$(/usr/bin/find "$backup_root" -mindepth 1 -maxdepth 1 -print -quit)" ] \
    || [ -n "$(/usr/bin/find "$displaced_backup_root" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    fail "FD-anchored rollback stranded the original under a substituted parent"
  fi
  [ -d "$lock" ] && [ ! -L "$lock" ] \
    || fail "ambiguous parent substitution did not retain its authoritative lock"
  lock_identity="$(/usr/bin/stat -f '%d:%i' "$lock")"
  staged_identity="$(/usr/bin/stat -f '%d:%i' "$staged")"

  set +e
  /bin/bash -c "$command" >"$fixture/competing.out" 2>&1
  competing_status=$?
  set -e
  [ "$competing_status" -ne 0 ] \
    || fail "competing apply became a second writer while the ambiguous lock existed"
  verify_stale_target \
    "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  assert_equal "$lock_identity" "$(/usr/bin/stat -f '%d:%i' "$lock")" \
    "retained ambiguous lock identity after competing apply"
  assert_equal "$staged_identity" "$(/usr/bin/stat -f '%d:%i' "$staged")" \
    "staged evidence identity after competing apply"
  assert_output_contains "$fixture/apply.out" \
    "kernel rollback restored the source but a rename parent remains substituted"
  assert_output_contains "$fixture/apply.out" \
    "ambiguous kernel-rename outcome"
  assert_output_contains "$fixture/competing.out" \
    "Another MicAI install is active or left an ambiguous lock"
  remove_exact_fixture_root "$fixture"
  echo "PASS post-kernel parent substitution restored target, retained fail-closed lock, and cleaned only its fixture root"
}

test_post_kernel_rollback_state_revalidation() {
  local fixture
  local plan
  local command
  local backup
  local staged
  local target
  local lock
  local mutation
  local original_inode
  local original_executable_hash
  local original_plist_hash
  local lock_identity
  local staged_identity
  local status
  local competing_status

  fixture="$(new_fixture post-kernel-state)"
  make_stale_target "$fixture"
  target="$fixture/Applications/MicAI.app"
  original_inode="$(/usr/bin/stat -f '%i' "$target")"
  original_executable_hash="$(sha256_file "$target/Contents/MacOS/MicAI")"
  original_plist_hash="$(sha256_file "$target/Contents/Info.plist")"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"
  backup="$(plan_value "$plan" "Recoverable backup")"
  staged="$(plan_value "$plan" "Staged copy")"
  lock="$fixture/Applications/.MicAI-install.lock"

  start_hooked_apply \
    "$fixture" "$command" "inside-rename-after-kernel" "$fixture/apply.out"
  wait_for_hook "$fixture" "inside-rename-after-kernel"
  path_exists "$backup" \
    || fail "post-kernel state hook did not observe the reviewed original at its destination"
  if path_exists "$target"; then
    fail "post-kernel state hook still found the reviewed original at its source"
  fi
  mutation="$backup/Contents/Resources/post-kernel-unreviewed-state.txt"
  printf 'mutation injected after the kernel rename\n' >"$mutation"
  release_hook
  finish_hooked_apply
  status="$ACTIVE_APPLY_STATUS"

  [ "$status" -ne 0 ] \
    || fail "post-kernel reviewed-state mutation unexpectedly installed"
  [ -d "$target" ] && [ ! -L "$target" ] \
    || fail "post-kernel state rollback did not restore a physical target"
  if path_exists "$backup"; then
    fail "post-kernel state rollback left the reviewed-original destination occupied"
  fi
  [ -f "$target/Contents/Resources/post-kernel-unreviewed-state.txt" ] \
    || fail "post-kernel state rollback did not expose the injected mismatch for inspection"
  assert_equal "$original_inode" "$(/usr/bin/stat -f '%i' "$target")" \
    "post-kernel state rollback target inode"
  assert_equal "$original_executable_hash" \
    "$(sha256_file "$target/Contents/MacOS/MicAI")" \
    "post-kernel state rollback executable hash"
  assert_equal "$original_plist_hash" \
    "$(sha256_file "$target/Contents/Info.plist")" \
    "post-kernel state rollback plist hash"
  [ -d "$lock" ] && [ ! -L "$lock" ] \
    || fail "post-kernel state mismatch did not retain its authoritative lock"
  lock_identity="$(/usr/bin/stat -f '%d:%i' "$lock")"
  staged_identity="$(/usr/bin/stat -f '%d:%i' "$staged")"

  set +e
  /bin/sh -c "$command" >"$fixture/competing.out" 2>&1
  competing_status=$?
  set -e
  [ "$competing_status" -ne 0 ] \
    || fail "competing apply became a second writer after post-kernel state mismatch"
  assert_equal "$original_inode" "$(/usr/bin/stat -f '%i' "$target")" \
    "post-kernel state mismatch target inode after competing apply"
  assert_equal "$lock_identity" "$(/usr/bin/stat -f '%d:%i' "$lock")" \
    "post-kernel state mismatch retained lock identity"
  assert_equal "$staged_identity" "$(/usr/bin/stat -f '%d:%i' "$staged")" \
    "post-kernel state mismatch staged evidence identity"
  assert_output_contains "$fixture/apply.out" \
    "kernel rollback restored source differs from the exact reviewed manifest/signature state"
  assert_output_contains "$fixture/apply.out" \
    "ambiguous kernel-rename outcome"
  assert_output_contains "$fixture/apply.out" \
    "lock is intentionally retained"
  assert_output_contains "$fixture/competing.out" \
    "Another MicAI install is active or left an ambiguous lock"
  remove_exact_fixture_root "$fixture"
  echo "PASS post-kernel rollback revalidates exact state and retains a fail-closed lock on mismatch"
}

test_ambiguous_rename_preserves_lock() {
  local fixture
  local plan
  local command
  local backup
  local target
  local status

  fixture="$(new_fixture ambiguous-rename)"
  make_stale_target "$fixture"
  target="$fixture/Applications/MicAI.app"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"
  backup="$(plan_value "$plan" "Recoverable backup")"

  start_hooked_apply \
    "$fixture" "$command" "inside-rename-after-kernel" "$fixture/apply.out"
  wait_for_hook "$fixture" "inside-rename-after-kernel"
  path_exists "$backup" \
    || fail "ambiguous-rename hook did not observe the moved original"
  /bin/mkdir "$target"
  release_hook
  finish_hooked_apply
  status="$ACTIVE_APPLY_STATUS"

  [ "$status" -ne 0 ] || fail "ambiguous rename unexpectedly reported success"
  [ -d "$target" ] && [ ! -L "$target" ] \
    || fail "ambiguous rename deleted the external source-path occupant"
  path_exists "$backup" \
    || fail "ambiguous rename deleted the moved reviewed original"
  [ -d "$fixture/Applications/.MicAI-install.lock" ] \
    || fail "ambiguous rename did not preserve its FD-anchored lock"
  assert_output_contains "$fixture/apply.out" \
    "ambiguous kernel-rename outcome"
  assert_output_contains "$fixture/apply.out" \
    "lock is intentionally retained"
  echo "PASS ambiguous rename preserves paths and lock for inspection: $fixture"
}

test_install_root_substitution_lock() {
  local fixture
  local plan
  local command
  local displaced_root
  local target
  local original_inode
  local original_executable_hash
  local original_plist_hash
  local first_status
  local second_status

  fixture="$(new_fixture root-substitution)"
  make_stale_target "$fixture"
  target="$fixture/Applications/MicAI.app"
  original_inode="$(/usr/bin/stat -f '%i' "$target")"
  original_executable_hash="$(sha256_file "$target/Contents/MacOS/MicAI")"
  original_plist_hash="$(sha256_file "$target/Contents/Info.plist")"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"
  displaced_root="$fixture/displaced-Applications"

  start_hooked_apply \
    "$fixture" "$command" "after-install-lock" "$fixture/first.out"
  wait_for_hook "$fixture" "after-install-lock"
  /bin/mv "$fixture/Applications" "$displaced_root"
  /bin/mkdir "$fixture/Applications"

  set +e
  /bin/bash -c "$command" >"$fixture/second.out" 2>&1
  second_status=$?
  set -e
  [ "$second_status" -ne 0 ] \
    || fail "a second writer acquired a lock in a substituted install root"

  release_hook
  finish_hooked_apply
  first_status="$ACTIVE_APPLY_STATUS"
  [ "$first_status" -ne 0 ] \
    || fail "the first writer continued after install-root substitution"

  assert_equal "$original_inode" \
    "$(/usr/bin/stat -f '%i' "$displaced_root/MicAI.app")" \
    "root-substitution reviewed target inode"
  assert_equal "$original_executable_hash" \
    "$(sha256_file "$displaced_root/MicAI.app/Contents/MacOS/MicAI")" \
    "root-substitution reviewed target executable hash"
  assert_equal "$original_plist_hash" \
    "$(sha256_file "$displaced_root/MicAI.app/Contents/Info.plist")" \
    "root-substitution reviewed target plist hash"
  verify_target_manifest "$fixture" "$displaced_root/MicAI.app"
  [ -d "$displaced_root/.MicAI-install.lock" ] \
    || fail "the first writer lost its lock after root substitution"
  if [ -n "$(/usr/bin/find "$fixture/Applications" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    fail "an installer wrote into the substituted visible install root"
  fi
  assert_output_contains "$fixture/first.out" \
    "visible install root differs from the held root descriptor"
  assert_output_contains "$fixture/second.out" \
    "install-root device/inode differs from the reviewed plan"
  echo "PASS install-root substitution blocks both writers and retains the original lock: $fixture"
}

test_exclusive_rename_identity() {
  local fixture
  local plan
  local command
  local staged
  local target
  local staged_identity
  local target_identity
  local status

  fixture="$(new_fixture rename-identity)"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"
  staged="$(plan_value "$plan" "Staged copy")"
  target="$fixture/Applications/MicAI.app"

  start_hooked_apply \
    "$fixture" "$command" "before-replacement-rename" "$fixture/apply.out"
  wait_for_hook "$fixture" "before-replacement-rename"
  staged_identity="$(/usr/bin/stat -f '%d:%i' "$staged")"
  release_hook
  finish_hooked_apply
  status="$ACTIVE_APPLY_STATUS"

  assert_equal "0" "$status" "exclusive rename identity apply status"
  target_identity="$(/usr/bin/stat -f '%d:%i' "$target")"
  assert_equal "$staged_identity" "$target_identity" \
    "exclusive rename destination device/inode"
  /usr/bin/codesign --verify --deep --strict "$target"
  if path_exists "$fixture/Applications/.MicAI-install.lock"; then
    fail "exclusive rename identity test left the install lock"
  fi
  echo "PASS exclusive rename preserved device/inode: $fixture ($target_identity)"
}

test_missing_replacement_rollback() {
  local fixture
  local plan
  local command
  local backup
  local target
  local removed_replacement
  local original_inode
  local original_executable_hash
  local original_plist_hash
  local status

  fixture="$(new_fixture missing-replacement)"
  make_stale_target "$fixture"
  target="$fixture/Applications/MicAI.app"
  removed_replacement="$fixture/externally-removed-replacement.app"
  original_inode="$(/usr/bin/stat -f '%i' "$target")"
  original_executable_hash="$(sha256_file "$target/Contents/MacOS/MicAI")"
  original_plist_hash="$(sha256_file "$target/Contents/Info.plist")"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"
  backup="$(plan_value "$plan" "Recoverable backup")"

  start_hooked_apply \
    "$fixture" "$command" "after-replacement-rename" "$fixture/apply.out"
  wait_for_hook "$fixture" "after-replacement-rename"
  /bin/mv "$target" "$removed_replacement"
  release_hook
  finish_hooked_apply
  status="$ACTIVE_APPLY_STATUS"

  [ "$status" -ne 0 ] || fail "missing replacement fixture unexpectedly succeeded"
  verify_stale_target \
    "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  path_exists "$removed_replacement" \
    || fail "externally removed replacement was not retained by the fixture"
  if path_exists "$backup"; then
    fail "reviewed backup remained after successful rollback restore"
  fi
  if path_exists "$fixture/Applications/.MicAI-install.lock"; then
    fail "missing replacement rollback left the install lock"
  fi
  assert_output_contains "$fixture/apply.out" \
    "the failed replacement is already absent; continuing restore"
  assert_output_contains "$fixture/apply.out" \
    "Verified rollback restored the reviewed original target state"
  echo "PASS missing replacement rollback: $fixture"
}

test_same_plan_race() {
  local fixture
  local plan
  local command
  local first_pid
  local second_pid
  local first_status
  local second_status
  local winners=0
  local target
  local root_device
  local target_device
  local backup_device

  fixture="$(new_fixture same-plan-race)"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"
  target="$fixture/Applications/MicAI.app"

  /bin/bash -c "$command" >"$fixture/first.out" 2>&1 &
  ACTIVE_APPLY_PID=$!
  first_pid="$ACTIVE_APPLY_PID"
  /bin/bash -c "$command" >"$fixture/second.out" 2>&1 &
  ACTIVE_SECONDARY_PID=$!
  second_pid="$ACTIVE_SECONDARY_PID"
  set +e
  wait "$first_pid"
  first_status=$?
  wait "$second_pid"
  second_status=$?
  set -e
  ACTIVE_APPLY_PID=""
  ACTIVE_SECONDARY_PID=""
  [ "$first_status" -eq 0 ] && winners=$((winners + 1))
  [ "$second_status" -eq 0 ] && winners=$((winners + 1))
  assert_equal "1" "$winners" "same-plan race winner count"
  /usr/bin/codesign --verify --deep --strict "$target"
  assert_equal \
    "$(sha256_file "$SOURCE_APP/Contents/MacOS/MicAI")" \
    "$(sha256_file "$target/Contents/MacOS/MicAI")" \
    "same-plan race target executable hash"
  if path_exists "$fixture/Applications/.MicAI-install.lock"; then
    fail "same-plan race left the install lock"
  fi
  root_device="$(/usr/bin/stat -f '%d' "$fixture/Applications")"
  target_device="$(/usr/bin/stat -f '%d' "$target")"
  backup_device="$(/usr/bin/stat -f '%d' "$fixture/Applications/.MicAI-backups")"
  assert_equal "$root_device" "$target_device" "same-plan race target device"
  assert_equal "$root_device" "$backup_device" "same-plan race backup device"
  echo "PASS same reviewed-plan race: $fixture (statuses $first_status/$second_status)"
}

test_lock_inode_substitution_competing_writer() {
  local fixture
  local plan
  local command
  local target
  local lock
  local replacement_lock_identity
  local original_inode
  local original_executable_hash
  local original_plist_hash
  local first_status
  local second_status

  fixture="$(new_fixture lock-substitution)"
  make_stale_target "$fixture"
  target="$fixture/Applications/MicAI.app"
  lock="$fixture/Applications/.MicAI-install.lock"
  original_inode="$(/usr/bin/stat -f '%i' "$target")"
  original_executable_hash="$(sha256_file "$target/Contents/MacOS/MicAI")"
  original_plist_hash="$(sha256_file "$target/Contents/Info.plist")"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"

  start_hooked_apply \
    "$fixture" "$command" "before-original-backup-rename" "$fixture/first.out"
  wait_for_hook "$fixture" "before-original-backup-rename"
  /bin/rmdir "$lock"
  /bin/mkdir "$lock"
  replacement_lock_identity="$(/usr/bin/stat -f '%d:%i' "$lock")"

  set +e
  /bin/bash -c "$command" >"$fixture/second.out" 2>&1
  second_status=$?
  set -e
  [ "$second_status" -ne 0 ] \
    || fail "competing writer acquired a substituted transaction lock"

  release_hook
  finish_hooked_apply
  first_status="$ACTIVE_APPLY_STATUS"
  [ "$first_status" -ne 0 ] \
    || fail "first writer continued after its lock inode was substituted"

  verify_stale_target \
    "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  assert_equal "$replacement_lock_identity" \
    "$(/usr/bin/stat -f '%d:%i' "$lock")" \
    "substituted lock identity was preserved"
  assert_output_contains "$fixture/first.out" \
    "visible install lock differs from the held lock descriptor"
  assert_output_contains "$fixture/second.out" \
    "Another MicAI install is active or left an ambiguous lock"
  echo "PASS lock-inode substitution and competing-writer rejection: $fixture"
}

test_staged_state_mutation_before_forward_rename() {
  local fixture
  local plan
  local command
  local staged
  local target
  local status

  fixture="$(new_fixture staged-state-race)"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"
  staged="$(plan_value "$plan" "Staged copy")"
  target="$fixture/Applications/MicAI.app"

  start_hooked_apply \
    "$fixture" "$command" "before-replacement-rename" "$fixture/apply.out"
  wait_for_hook "$fixture" "before-replacement-rename"
  /bin/chmod 600 "$staged/Contents/Info.plist"
  release_hook
  finish_hooked_apply
  status="$ACTIVE_APPLY_STATUS"

  [ "$status" -ne 0 ] || fail "mutated staged source unexpectedly installed"
  if path_exists "$target"; then
    fail "state-bound rename committed an unreviewed staged source"
  fi
  assert_equal "600" "$(/usr/bin/stat -f '%Lp' "$staged/Contents/Info.plist")" \
    "externally mutated staged mode"
  if path_exists "$fixture/Applications/.MicAI-install.lock"; then
    fail "rejected staged-state mutation left the install lock"
  fi
  assert_output_contains "$fixture/apply.out" \
    "exclusive rename source differs from the exact reviewed manifest/signature state"
  echo "PASS staged-source mutation rejected inside the FD-anchored rename: $fixture"
}

test_backup_state_mutation_before_restore_rename() {
  local fixture
  local plan
  local command
  local backup
  local failed
  local target
  local lock
  local status

  fixture="$(new_fixture restore-state-race)"
  make_stale_target "$fixture"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"
  backup="$(plan_value "$plan" "Recoverable backup")"
  failed="$(plan_value "$plan" "Failed replacement quarantine")"
  target="$fixture/Applications/MicAI.app"
  lock="$fixture/Applications/.MicAI-install.lock"

  start_hooked_apply \
    "$fixture" "$command" "before-original-restore-rename" "$fixture/apply.out"
  wait_for_hook "$fixture" "before-original-restore-rename"
  path_exists "$backup" || fail "restore-state hook did not observe the reviewed backup"
  if path_exists "$target"; then
    fail "restore-state hook observed a target before the restore rename"
  fi
  path_exists "$failed" || fail "restore-state hook did not observe quarantined replacement"
  /bin/chmod 600 "$backup/Contents/Info.plist"
  release_hook
  finish_hooked_apply
  status="$ACTIVE_APPLY_STATUS"

  [ "$status" -ne 0 ] || fail "mutated backup unexpectedly restored"
  if path_exists "$target"; then
    fail "state-bound restore committed an unreviewed backup"
  fi
  path_exists "$backup" || fail "mutated reviewed backup was not retained for inspection"
  path_exists "$failed" || fail "quarantined replacement was not retained for inspection"
  [ -d "$lock" ] && [ ! -L "$lock" ] \
    || fail "incomplete restore did not retain the authoritative lock"
  assert_output_contains "$fixture/apply.out" \
    "exclusive rename source differs from the exact reviewed manifest/signature state"
  assert_output_contains "$fixture/apply.out" \
    "lock and evidence are retained"
  echo "PASS nested backup mutation rejected before restore commit: $fixture"
}

test_symlink_hardlink_topology_binding() {
  local fixture
  local plan
  local command
  local target
  local links
  local original_inode
  local original_executable_hash
  local original_plist_hash
  local normalized_source
  local normalized_stage
  local source_state
  local stage_state
  local normalized_status
  local status

  fixture="$(new_fixture symlink-hardlinks)"
  normalized_source="$fixture/normalized-source.app"
  normalized_stage="$fixture/normalized-stage.app"
  /bin/mkdir "$normalized_source" "$normalized_stage"
  printf 'same normalized content\n' >"$normalized_source/file"
  printf 'same normalized content\n' >"$normalized_stage/file"
  /bin/ln -s file "$normalized_source/link"
  /bin/ln -s file "$normalized_stage/link"
  /usr/bin/python3 - "$normalized_source" "$normalized_stage" <<'PY'
import os
import sys

for root in sys.argv[1:]:
    for name in (root, os.path.join(root, "file"), os.path.join(root, "link")):
        os.chown(
            name,
            os.geteuid(),
            os.getegid(),
            follow_symlinks=False,
        )
PY
  source_state="$(
    cd "$fixture"
    MICAI_INSTALL_DIR="$fixture/Applications" \
      MICAI_INTERNAL_STATE_HELPER=1 \
      MICAI_INTERNAL_BUNDLE_BASENAME=normalized-source.app \
      MICAI_INTERNAL_METADATA_POLICY=normalized \
      /bin/bash "$INSTALL_SCRIPT" --internal-bundle-state
  )"
  stage_state="$(
    cd "$fixture"
    MICAI_INSTALL_DIR="$fixture/Applications" \
      MICAI_INTERNAL_STATE_HELPER=1 \
      MICAI_INTERNAL_BUNDLE_BASENAME=normalized-stage.app \
      MICAI_INTERNAL_METADATA_POLICY=normalized \
      /bin/bash "$INSTALL_SCRIPT" --internal-bundle-state
  )"
  assert_equal "${source_state%%|*}" "${stage_state%%|*}" \
    "normalized independent-symlink source/stage manifest"
  /usr/bin/python3 - "$normalized_source" <<'PY'
import os
import sys

root = sys.argv[1]
os.link(
    os.path.join(root, "link"),
    os.path.join(root, "hard-linked-link"),
    follow_symlinks=False,
)
PY
  set +e
  (
    cd "$fixture"
    MICAI_INSTALL_DIR="$fixture/Applications" \
      MICAI_INTERNAL_STATE_HELPER=1 \
      MICAI_INTERNAL_BUNDLE_BASENAME=normalized-source.app \
      MICAI_INTERNAL_METADATA_POLICY=normalized \
      /bin/bash "$INSTALL_SCRIPT" --internal-bundle-state
  ) >"$fixture/normalized-hardlink.out" 2>&1
  normalized_status=$?
  set -e
  [ "$normalized_status" -ne 0 ] \
    || fail "normalized manifest accepted a hard-linked symlink"
  assert_output_contains "$fixture/normalized-hardlink.out" \
    "hard-linked files or symlinks are not allowed"

  make_stale_target "$fixture"
  target="$fixture/Applications/MicAI.app"
  links="$target/Contents/Resources/topology-links"
  /bin/mkdir "$links"
  printf 'shared symlink target\n' >"$links/same-target"
  /usr/bin/python3 - "$links" <<'PY'
import os
import sys

root = sys.argv[1]
os.symlink("same-target", os.path.join(root, "a"))
os.link(os.path.join(root, "a"), os.path.join(root, "b"), follow_symlinks=False)
os.symlink("same-target", os.path.join(root, "c"))
os.link(os.path.join(root, "c"), os.path.join(root, "d"), follow_symlinks=False)
PY
  /usr/bin/codesign --force --deep --sign - "$target" >/dev/null
  /usr/bin/codesign --verify --deep --strict "$target"
  original_inode="$(/usr/bin/stat -f '%i' "$target")"
  original_executable_hash="$(sha256_file "$target/Contents/MacOS/MicAI")"
  original_plist_hash="$(sha256_file "$target/Contents/Info.plist")"
  plan="$fixture/plan.txt"
  write_plan "$fixture" "$plan"
  command="$(plan_apply_command "$plan")"

  /usr/bin/python3 - "$links" <<'PY'
import os
import sys

root = sys.argv[1]
os.unlink(os.path.join(root, "b"))
os.unlink(os.path.join(root, "d"))
os.link(os.path.join(root, "c"), os.path.join(root, "b"), follow_symlinks=False)
os.link(os.path.join(root, "a"), os.path.join(root, "d"), follow_symlinks=False)
PY
  /usr/bin/codesign --verify --deep --strict "$target"
  capture_stale_target_manifest "$fixture"

  set +e
  /bin/bash -c "$command" >"$fixture/apply.out" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "changed symlink-hardlink topology unexpectedly installed"
  verify_stale_target \
    "$fixture" "$original_inode" "$original_executable_hash" "$original_plist_hash"
  assert_equal "$(/usr/bin/stat -f '%i' "$links/a")" \
    "$(/usr/bin/stat -f '%i' "$links/d")" "rewired symlink group a/d"
  assert_equal "$(/usr/bin/stat -f '%i' "$links/b")" \
    "$(/usr/bin/stat -f '%i' "$links/c")" "rewired symlink group b/c"
  if path_exists "$fixture/Applications/.MicAI-install.lock"; then
    fail "symlink-hardlink topology mismatch left the install lock"
  fi
  assert_output_contains "$fixture/apply.out" \
    "The installed target changed after acquiring the install lock"
  echo "PASS preserved manifest binds symlink-hardlink topology: $fixture"
}

test_plist_component_containment() {
  local keys=(
    CFBundleExecutable
    CFBundleIconFile
    CFBundleExecutable
    CFBundleExecutable
    CFBundleExecutable
    CFBundleExecutable
    CFBundleIconFile
    CFBundleIconFile
    CFBundleExecutable
    CFBundleExecutable
    CFBundleExecutable
    CFBundleExecutable
    CFBundleExecutable
    CFBundleExecutable
    CFBundleIconFile
    CFBundleIconFile
    CFBundleIconFile
    CFBundleIconFile
    CFBundleIconFile
    CFBundleIconFile
  )
  local values=(
    "../../../outside-sentinel"
    "../../../outside-sentinel"
    "nested/MicAI"
    ""
    "."
    ".."
    "MicAI.png"
    ".hidden.icns"
    $'\nMicAI'
    $'Mic\nAI'
    $'MicAI\n'
    $'\rMicAI'
    $'Mic\rAI'
    $'MicAI\r'
    $'\nMicAI'
    $'Mic\nAI'
    $'MicAI\n'
    $'\rMicAI'
    $'Mic\rAI'
    $'MicAI\r'
  )
  local names=(
    executable-traversal
    icon-traversal
    slash
    empty
    dot
    dotdot
    extension
    hidden
    executable-leading-lf
    executable-internal-lf
    executable-trailing-lf
    executable-leading-cr
    executable-internal-cr
    executable-trailing-cr
    icon-leading-lf
    icon-internal-lf
    icon-trailing-lf
    icon-leading-cr
    icon-internal-cr
    icon-trailing-cr
  )
  local index=0
  local fixture
  local target
  local plist
  local sentinel
  local sentinel_hash
  local plan
  local status

  while [ "$index" -lt "${#keys[@]}" ]; do
    fixture="$(new_fixture "plist-${names[$index]}")"
    target="$fixture/Applications/MicAI.app"
    /usr/bin/ditto "$SOURCE_APP" "$target"
    plist="$target/Contents/Info.plist"
    sentinel="$fixture/Applications/outside-sentinel"
    printf 'outside sentinel must never be read through plist traversal\n' >"$sentinel"
    sentinel_hash="$(sha256_file "$sentinel")"
    /bin/chmod 000 "$sentinel"
    /usr/bin/plutil -replace "${keys[$index]}" \
      -string "${values[$index]}" "$plist"
    plan="$fixture/plan.txt"

    set +e
    MICAI_INSTALL_DIR="$fixture/Applications" \
      /bin/bash "$INSTALL_SCRIPT" --plan >"$plan" 2>"$fixture/plan.err"
    status=$?
    set -e

    [ "$status" -ne 0 ] \
      || fail "unsafe plist component '${names[$index]}' produced a plan"
    [ -z "$(plan_apply_command "$plan")" ] \
      || fail "unsafe plist component '${names[$index]}' emitted an apply command"
    /bin/chmod 600 "$sentinel"
    assert_equal "$sentinel_hash" "$(sha256_file "$sentinel")" \
      "outside sentinel hash after '${names[$index]}' rejection"
    assert_output_not_contains "$plan" "$sentinel_hash"
    assert_output_not_contains "$fixture/plan.err" "$sentinel_hash"
    assert_output_not_contains "$fixture/plan.err" "outside-sentinel"
    assert_output_not_contains "$fixture/plan.err" "Permission denied"
    assert_output_contains "$fixture/plan.err" "Unsafe ${keys[$index]} component"
    index=$((index + 1))
  done
  echo "PASS plist-derived paths reject traversal, unsafe names, and losslessly decoded LF/CR positions"
}

test_shell_safe_apply_command_roundtrip() {
  local fixture
  local install_root
  local plan
  local command
  local target
  local require_target
  local status

  fixture="$(new_fixture posix-quote)"
  install_root="$fixture/Applications apostrophe' spaces ; "
  install_root="${install_root}"'dollar$(printf EXECUTED_%s DOLLAR >&2) backtick`printf EXECUTED_%s BACKTICK >&2` glob*? amp& brackets[]'
  install_root="${install_root}"$'\n''literal-newline'
  /bin/mkdir "$install_root"
  plan="$fixture/plan.txt"
  MICAI_INSTALL_DIR="$install_root" \
    /bin/bash "$INSTALL_SCRIPT" --plan >"$plan"
  command="$(plan_apply_command "$plan")"
  [ -n "$command" ] || fail "quoted custom-root plan omitted its apply command"
  case "$command" in
    *$'\n'*)
      ;;
    *)
      fail "POSIX-quoted apply command did not preserve the custom-root newline"
      ;;
  esac
  assert_output_contains "$plan" "'\\''"
  case "$command" in
    *" '--apply'")
      ;;
    *)
      fail "POSIX-quoted apply command did not end with the exact encoded --apply token"
      ;;
  esac

  set +e
  /bin/sh -c "$command" >"$fixture/apply.out" 2>&1
  status=$?
  set -e

  assert_equal "0" "$status" "POSIX-shell exact apply command status"
  assert_output_not_contains "$fixture/apply.out" "EXECUTED_DOLLAR"
  assert_output_not_contains "$fixture/apply.out" "EXECUTED_BACKTICK"
  target="$install_root/MicAI.app"
  require_target="$target/Contents/MacOS/MicAI"
  [ -x "$require_target" ] \
    || fail "POSIX-quoted exact command did not install at the byte-exact root"
  assert_equal "$(sha256_file "$SOURCE_APP/Contents/MacOS/MicAI")" \
    "$(sha256_file "$require_target")" "quoted-root target executable hash"
  /usr/bin/codesign --verify --deep --strict "$target"
  if path_exists "$install_root/.MicAI-install.lock"; then
    fail "quoted exact command left the install lock"
  fi
  remove_exact_fixture_root "$fixture"
  echo "PASS POSIX-shell exact command round-trips apostrophe/newline/spaces/metacharacters without executing payloads"
}

if [ ! -d "$SOURCE_APP" ]; then
  fail "build dist/MicAI.app before running this fixture suite"
fi
/usr/bin/codesign --verify --deep --strict "$SOURCE_APP"

pgrep_status=0
/usr/bin/pgrep -x MicAI >/dev/null 2>&1 || pgrep_status=$?
case "$pgrep_status" in
  0)
    echo "BLOCKED/SKIPPED: a MicAI process is running, so the production apply guard" >&2
    echo "prevents every installer fixture. No invariant was run and no guard was bypassed." >&2
    exit 77
    ;;
  1)
    ;;
  *)
    echo "BLOCKED/SKIPPED: process inspection is unavailable, so the production" >&2
    echo "apply guard cannot prove MicAI is stopped. No invariant was run." >&2
    exit 77
    ;;
esac

if [ "$SUITE_MODE" = "--targeted-review-six" ]; then
  test_post_kernel_rollback_state_revalidation
  test_plist_component_containment
  test_shell_safe_apply_command_roundtrip
  echo "All three Review 6 targeted fixtures passed. Temporary evidence was confined to /private/tmp."
  exit 0
fi
if [ "$SUITE_MODE" = "--targeted-review-seven" ]; then
  test_plist_component_containment
  test_shell_safe_apply_command_roundtrip
  echo "Both Review 7 targeted fixtures passed. Temporary evidence was confined to /private/tmp."
  exit 0
fi
if [ "$SUITE_MODE" = "--targeted-review-eight" ]; then
  test_trailing_slash_install_root_rejected
  echo "The Review 8 trailing-slash fixture passed. Temporary evidence was confined to /private/tmp."
  exit 0
fi
if [ "$SUITE_MODE" = "--targeted-review-eleven" ]; then
  test_stale_target_verifier_full_manifest
  echo "The Review 11 full-manifest verifier fixture passed. Temporary evidence was confined to /private/tmp."
  exit 0
fi
if [ "$SUITE_MODE" = "--targeted-fifth-review" ]; then
  test_symlink_hardlink_topology_binding
  test_plist_component_containment
  test_lock_inode_substitution_competing_writer
  test_staged_state_mutation_before_forward_rename
  test_backup_state_mutation_before_restore_rename
  test_shell_safe_apply_command_roundtrip
  echo "All six fifth-review targeted fixtures passed. Temporary evidence was left under /private/tmp."
  exit 0
fi
if [ "$SUITE_MODE" = "--targeted-transaction-regression" ]; then
  test_exclusive_backup_destination_directory
  test_bound_backup_parent_substitution
  test_post_kernel_parent_substitution_rollback
  test_ambiguous_rename_preserves_lock
  test_install_root_substitution_lock
  test_exclusive_rename_identity
  test_missing_replacement_rollback
  test_same_plan_race
  echo "All eight state-transaction regression fixtures passed. Temporary evidence was left under /private/tmp."
  exit 0
fi

test_dangling_staged_symlink
test_symlinked_backup_root
test_symlinked_target
test_stale_target_verifier_full_manifest
test_trailing_slash_install_root_rejected
test_hook_scope_rejected
test_complete_target_manifest_binding
test_target_metadata_binding
test_manifest_snapshot_mutation
test_symlink_hardlink_topology_binding
test_plist_component_containment
test_exclusive_backup_destination_directory
test_bound_backup_parent_substitution
test_post_kernel_parent_substitution_rollback
test_post_kernel_rollback_state_revalidation
test_ambiguous_rename_preserves_lock
test_install_root_substitution_lock
test_lock_inode_substitution_competing_writer
test_staged_state_mutation_before_forward_rename
test_backup_state_mutation_before_restore_rename
test_exclusive_rename_identity
test_missing_replacement_rollback
test_shell_safe_apply_command_roundtrip
test_same_plan_race
echo "All MicAI install safety fixtures passed. Temporary evidence was left under /private/tmp."
