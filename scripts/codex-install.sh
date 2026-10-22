#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SOURCE_APP="$PROJECT_ROOT/dist/MicAI.app"
INSTALL_ROOT="${MICAI_INSTALL_DIR:-${HOME:?}/Applications}"
MODE="${1:---plan}"
INSTALL_ID="${MICAI_INSTALL_ID:-$(/bin/date -u +%Y%m%dT%H%M%SZ)}"
PYTHON_BIN="/usr/bin/python3"
TEST_HOOK_POINT="${MICAI_INSTALL_TEST_HOOK_POINT:-}"
TEST_HOOK_DIR="${MICAI_INSTALL_TEST_HOOK_DIR:-}"
TEST_HOOK_ENABLED=false

usage() {
  echo "Usage: bash scripts/codex-install.sh [--plan | --apply]"
  echo "  --plan   Inspect source and target, then print the gated install operation."
  echo "  --apply  Perform only the exact target- and hash-bound operation from a plan."
}

if [ "$#" -gt 1 ]; then
  usage >&2
  exit 2
fi

case "$MODE" in
  --plan | --apply | --internal-bundle-state)
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [[ "$INSTALL_ROOT" != /* ]] || [ "$INSTALL_ROOT" = "/" ]; then
  echo "MICAI_INSTALL_DIR must be an absolute directory other than /." >&2
  exit 1
fi

case "$INSTALL_ROOT" in
  */)
    echo "MICAI_INSTALL_DIR must not end with a trailing slash." >&2
    exit 1
    ;;
  *"/../"* | */.. | *"/./"* | */.)
    echo "MICAI_INSTALL_DIR contains an unsupported path component." >&2
    exit 1
    ;;
esac

if [[ ! "$INSTALL_ID" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]; then
  echo "MICAI_INSTALL_ID must use UTC form YYYYMMDDTHHMMSSZ." >&2
  exit 1
fi

TARGET_APP="$INSTALL_ROOT/MicAI.app"
BACKUP_ROOT="$INSTALL_ROOT/.MicAI-backups"
BACKUP_APP="$BACKUP_ROOT/MicAI-before-$INSTALL_ID.app"
STAGED_APP="$INSTALL_ROOT/.MicAI-install-$INSTALL_ID.app"
FAILED_APP="$INSTALL_ROOT/.MicAI-failed-$INSTALL_ID.app"
LOCK_DIR="$INSTALL_ROOT/.MicAI-install.lock"

sha256_file() {
  /usr/bin/shasum -a 256 <"$1" | /usr/bin/awk '{print $1}'
}

path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

device_id() {
  /usr/bin/stat -f '%d' "$1" 2>/dev/null
}

require_physical_directory() {
  local path="$1"
  local label="$2"

  if [ -L "$path" ]; then
    echo "$label must not be a symbolic link: $path" >&2
    return 1
  fi
  if [ ! -d "$path" ]; then
    echo "$label must be a physical directory: $path" >&2
    return 1
  fi
}

require_same_device() {
  local reference="$1"
  local candidate="$2"
  local label="$3"
  local reference_device
  local candidate_device

  if ! reference_device="$(device_id "$reference")" \
    || ! candidate_device="$(device_id "$candidate")"; then
    echo "Could not determine device IDs for $label." >&2
    return 1
  fi
  if [ "$reference_device" != "$candidate_device" ]; then
    echo "$label must be on the install-root device." >&2
    echo "  Install root: $reference (device $reference_device)" >&2
    echo "  Candidate: $candidate (device $candidate_device)" >&2
    return 1
  fi
}

hash_or_missing() {
  if [ -L "$1" ]; then
    echo "<unsupported-symlink>"
  elif [ -f "$1" ]; then
    sha256_file "$1"
  else
    echo "<missing>"
  fi
}

path_identity() {
  /usr/bin/stat -f '%d:%i' "$1" 2>/dev/null
}

print_shell_word() {
  local value="$1"
  local apostrophe="'"
  local prefix

  printf "'"
  while [[ "$value" == *"$apostrophe"* ]]; do
    prefix=${value%%"$apostrophe"*}
    printf "%s'\\\\''" "$prefix"
    value=${value#*"$apostrophe"}
  done
  printf "%s'" "$value"
}

print_shell_assignment() {
  local name="$1"
  local value="$2"
  printf '%s=' "$name"
  print_shell_word "$value"
}

bundle_manifest_sha256() {
  local bundle="$1"
  local metadata_policy="${2:-preserve}"
  local hook_context="${3:-none}"

  "$PYTHON_BIN" - \
    "$bundle" \
    "$metadata_policy" \
    "$hook_context" \
    "$TEST_HOOK_ENABLED" \
    "$TEST_HOOK_POINT" \
    "$TEST_HOOK_DIR" <<'PY'
import ctypes
import errno
import hashlib
import os
import stat
import struct
import sys
import time

root_path = os.fsencode(sys.argv[1])
metadata_policy = sys.argv[2]
hook_context = sys.argv[3]
test_hook_enabled = sys.argv[4] == "true"
test_hook_point = sys.argv[5]
test_hook_directory = os.fsencode(sys.argv[6]) if sys.argv[6] else b""
if metadata_policy not in ("preserve", "normalized"):
    raise SystemExit(f"Unsupported bundle metadata policy: {metadata_policy}")

libc = ctypes.CDLL(None, use_errno=True)
flistxattr = libc.flistxattr
flistxattr.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int]
flistxattr.restype = ctypes.c_ssize_t
fgetxattr = libc.fgetxattr
fgetxattr.argtypes = [
    ctypes.c_int,
    ctypes.c_char_p,
    ctypes.c_void_p,
    ctypes.c_size_t,
    ctypes.c_uint32,
    ctypes.c_int,
]
fgetxattr.restype = ctypes.c_ssize_t
listxattr = libc.listxattr
listxattr.argtypes = [ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int]
listxattr.restype = ctypes.c_ssize_t
getxattr = libc.getxattr
getxattr.argtypes = [
    ctypes.c_char_p,
    ctypes.c_char_p,
    ctypes.c_void_p,
    ctypes.c_size_t,
    ctypes.c_uint32,
    ctypes.c_int,
]
getxattr.restype = ctypes.c_ssize_t
acl_get_fd_np = libc.acl_get_fd_np
acl_get_fd_np.argtypes = [ctypes.c_int, ctypes.c_int]
acl_get_fd_np.restype = ctypes.c_void_p
acl_get_link_np = libc.acl_get_link_np
acl_get_link_np.argtypes = [ctypes.c_char_p, ctypes.c_int]
acl_get_link_np.restype = ctypes.c_void_p
acl_to_text = libc.acl_to_text
acl_to_text.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ssize_t)]
acl_to_text.restype = ctypes.c_void_p
acl_free = libc.acl_free
acl_free.argtypes = [ctypes.c_void_p]
acl_free.restype = ctypes.c_int

ACL_TYPE_EXTENDED = 0x00000100
XATTR_NOFOLLOW = 0x0001
OPEN_DIRECTORY = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
OPEN_FILE = os.O_RDONLY | os.O_NOFOLLOW
EMPTY_ACL_ERRNOS = {errno.ENOENT, errno.EINVAL, errno.ENOTSUP, errno.EOPNOTSUPP}


def stable_identity(value):
    return (
        value.st_dev,
        value.st_ino,
        value.st_mode,
        value.st_nlink,
        value.st_uid,
        value.st_gid,
        value.st_size,
        value.st_mtime_ns,
        value.st_ctime_ns,
        getattr(value, "st_flags", 0),
    )


def object_metadata(value):
    return (
        value.st_mode,
        value.st_nlink,
        value.st_uid,
        value.st_gid,
        getattr(value, "st_flags", 0),
    )


def read_xattr_names(function, first_argument, options):
    size = function(first_argument, None, 0, options)
    if size < 0:
        error_number = ctypes.get_errno()
        if error_number in (errno.ENOTSUP, errno.EOPNOTSUPP):
            return []
        raise OSError(error_number, os.strerror(error_number))
    if size == 0:
        return []
    buffer = ctypes.create_string_buffer(size)
    actual = function(first_argument, buffer, size, options)
    if actual < 0:
        error_number = ctypes.get_errno()
        raise OSError(error_number, os.strerror(error_number))
    if actual != size:
        raise RuntimeError("extended-attribute names changed while reading")
    return sorted(name for name in bytes(buffer.raw[:actual]).split(b"\0") if name)


def read_xattr_value(function, first_argument, name, options):
    size = function(first_argument, name, None, 0, 0, options)
    if size < 0:
        error_number = ctypes.get_errno()
        raise OSError(error_number, os.strerror(error_number))
    if size == 0:
        return b""
    buffer = ctypes.create_string_buffer(size)
    actual = function(first_argument, name, buffer, size, 0, options)
    if actual < 0:
        error_number = ctypes.get_errno()
        raise OSError(error_number, os.strerror(error_number))
    if actual != size:
        raise RuntimeError(f"extended attribute changed while reading: {name!r}")
    return bytes(buffer.raw[:actual])


def fd_xattrs(descriptor):
    names_before = read_xattr_names(flistxattr, descriptor, 0)
    values = [(name, read_xattr_value(fgetxattr, descriptor, name, 0)) for name in names_before]
    names_after = read_xattr_names(flistxattr, descriptor, 0)
    if names_before != names_after:
        raise RuntimeError("extended-attribute names changed during snapshot")
    return values


def path_xattrs(path):
    names_before = read_xattr_names(listxattr, path, XATTR_NOFOLLOW)
    values = [
        (name, read_xattr_value(getxattr, path, name, XATTR_NOFOLLOW))
        for name in names_before
    ]
    names_after = read_xattr_names(listxattr, path, XATTR_NOFOLLOW)
    if names_before != names_after:
        raise RuntimeError("symlink extended-attribute names changed during snapshot")
    return values


def acl_text_from_pointer(pointer):
    if not pointer:
        error_number = ctypes.get_errno()
        if error_number in EMPTY_ACL_ERRNOS:
            return b""
        raise OSError(error_number, os.strerror(error_number))
    try:
        length = ctypes.c_ssize_t()
        text_pointer = acl_to_text(pointer, ctypes.byref(length))
        if not text_pointer:
            error_number = ctypes.get_errno()
            raise OSError(error_number, os.strerror(error_number))
        try:
            return ctypes.string_at(text_pointer, length.value)
        finally:
            acl_free(text_pointer)
    finally:
        acl_free(pointer)


def fd_acl(descriptor):
    ctypes.set_errno(0)
    return acl_text_from_pointer(acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED))


def path_acl(path):
    ctypes.set_errno(0)
    return acl_text_from_pointer(acl_get_link_np(path, ACL_TYPE_EXTENDED))


def add_blob(target, value):
    target.update(struct.pack(">Q", len(value)))
    target.update(value)


def add_metadata(target, value, xattrs, acl):
    mode, links, owner, group, flags = object_metadata(value)
    target.update(struct.pack(">IQQQQ", mode, links, owner, group, flags))
    target.update(struct.pack(">Q", len(xattrs)))
    for name, data in xattrs:
        add_blob(target, name)
        add_blob(target, data)
    add_blob(target, acl)


def require_normalized(relative_path, value, xattrs, acl):
    if metadata_policy != "normalized":
        return
    label = os.fsdecode(relative_path) or "."
    if value.st_uid != os.geteuid() or value.st_gid != os.getegid():
        raise RuntimeError(f"non-normalized ownership at {label}")
    if getattr(value, "st_flags", 0) != 0:
        raise RuntimeError(f"non-normalized file flags at {label}")
    if xattrs:
        raise RuntimeError(f"extended attributes are not allowed at {label}")
    if acl:
        raise RuntimeError(f"extended ACLs are not allowed at {label}")
    if (stat.S_ISREG(value.st_mode) or stat.S_ISLNK(value.st_mode)) \
        and value.st_nlink != 1:
        raise RuntimeError(f"hard-linked files or symlinks are not allowed at {label}")


def snapshot_once():
    manifest = hashlib.sha256()
    hardlink_anchors = {}

    def record(kind, relative_path, value, xattrs, acl, payload=b""):
        require_normalized(relative_path, value, xattrs, acl)
        manifest.update(kind)
        add_blob(manifest, relative_path)
        add_metadata(manifest, value, xattrs, acl)
        add_blob(manifest, payload)

    def walk_directory(descriptor, relative_path):
        before = os.fstat(descriptor)
        if not stat.S_ISDIR(before.st_mode):
            raise RuntimeError(f"not a physical directory: {os.fsdecode(relative_path)}")
        xattrs = fd_xattrs(descriptor)
        acl = fd_acl(descriptor)
        record(b"D", relative_path, before, xattrs, acl)

        names = sorted(os.fsencode(name) for name in os.listdir(descriptor))
        for name in names:
            child_relative = name if not relative_path else relative_path + b"/" + name
            child_before = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
            child_path = root_path + b"/" + child_relative

            if stat.S_ISDIR(child_before.st_mode):
                child_descriptor = os.open(name, OPEN_DIRECTORY, dir_fd=descriptor)
                try:
                    opened = os.fstat(child_descriptor)
                    if stable_identity(opened) != stable_identity(child_before):
                        raise RuntimeError(
                            f"directory changed while opening: {os.fsdecode(child_relative)}"
                        )
                    walk_directory(child_descriptor, child_relative)
                finally:
                    os.close(child_descriptor)
            elif stat.S_ISREG(child_before.st_mode):
                child_descriptor = os.open(name, OPEN_FILE, dir_fd=descriptor)
                try:
                    opened_before = os.fstat(child_descriptor)
                    if stable_identity(opened_before) != stable_identity(child_before):
                        raise RuntimeError(
                            f"file changed while opening: {os.fsdecode(child_relative)}"
                        )
                    content = hashlib.sha256()
                    while True:
                        chunk = os.read(child_descriptor, 1024 * 1024)
                        if not chunk:
                            break
                        content.update(chunk)
                    xattrs = fd_xattrs(child_descriptor)
                    acl = fd_acl(child_descriptor)
                    opened_after = os.fstat(child_descriptor)
                    if stable_identity(opened_before) != stable_identity(opened_after):
                        raise RuntimeError(
                            f"file changed while hashing: {os.fsdecode(child_relative)}"
                        )
                    anchor = b""
                    if opened_after.st_nlink > 1:
                        key = (opened_after.st_dev, opened_after.st_ino)
                        anchor = hardlink_anchors.setdefault(key, child_relative)
                    payload = (
                        struct.pack(">Q", opened_after.st_size)
                        + content.digest()
                        + struct.pack(">Q", len(anchor))
                        + anchor
                    )
                    record(b"F", child_relative, opened_after, xattrs, acl, payload)
                finally:
                    os.close(child_descriptor)
            elif stat.S_ISLNK(child_before.st_mode):
                target = os.readlink(name, dir_fd=descriptor)
                if isinstance(target, str):
                    target = os.fsencode(target)
                xattrs = path_xattrs(child_path)
                acl = path_acl(child_path)
                child_after = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
                if stable_identity(child_before) != stable_identity(child_after):
                    raise RuntimeError(
                        f"symlink changed while hashing: {os.fsdecode(child_relative)}"
                    )
                anchor = b""
                if child_after.st_nlink > 1:
                    key = (child_after.st_dev, child_after.st_ino)
                    anchor = hardlink_anchors.setdefault(key, child_relative)
                payload = (
                    struct.pack(">Q", len(target))
                    + target
                    + struct.pack(">Q", len(anchor))
                    + anchor
                )
                record(b"L", child_relative, child_after, xattrs, acl, payload)
            else:
                raise RuntimeError(
                    f"unsupported bundle entry type: {os.fsdecode(child_relative)}"
                )

        after = os.fstat(descriptor)
        if stable_identity(before) != stable_identity(after):
            raise RuntimeError(
                f"directory changed while hashing: {os.fsdecode(relative_path) or '.'}"
            )

    root_before = os.lstat(root_path)
    root_descriptor = os.open(root_path, OPEN_DIRECTORY)
    try:
        opened_root = os.fstat(root_descriptor)
        if stable_identity(root_before) != stable_identity(opened_root):
            raise RuntimeError("bundle root changed while opening")
        walk_directory(root_descriptor, b"")
        root_after = os.lstat(root_path)
        if stable_identity(root_before) != stable_identity(root_after):
            raise RuntimeError("bundle root changed during snapshot")
    finally:
        os.close(root_descriptor)
    return manifest.hexdigest()


def run_between_snapshots_test_hook():
    if (
        not test_hook_enabled
        or hook_context != "reviewed-target"
        or test_hook_point != "inside-target-manifest-between-snapshots"
    ):
        return
    ready = os.path.join(
        test_hook_directory,
        b"inside-target-manifest-between-snapshots.ready",
    )
    release = os.path.join(
        test_hook_directory,
        b"inside-target-manifest-between-snapshots.release",
    )
    if os.path.lexists(ready) or os.path.lexists(release):
        raise RuntimeError("manifest test hook marker is already occupied")
    os.mkdir(ready, 0o700)
    while not os.path.lexists(release):
        time.sleep(0.01)
    release_stat = os.lstat(release)
    if not stat.S_ISDIR(release_stat.st_mode):
        raise RuntimeError("manifest test release marker is not a physical directory")


try:
    first = snapshot_once()
    run_between_snapshots_test_hook()
    second = snapshot_once()
    if first != second:
        raise RuntimeError("two complete bundle snapshots did not match")
except (OSError, RuntimeError) as error:
    print(f"Could not create a stable bundle-state manifest: {error}", file=sys.stderr)
    sys.exit(1)

print(second)
PY
}

bundle_manifest_or_missing() {
  if ! path_exists "$1"; then
    echo "<missing>"
    return 0
  fi
  if [ -L "$1" ] || [ ! -d "$1" ]; then
    echo "Cannot fingerprint a nonphysical app bundle: $1" >&2
    return 1
  fi
  bundle_manifest_sha256 "$1" preserve
}

LAST_RENAME_SOURCE_IDENTITY=""
LAST_RENAME_DESTINATION_IDENTITY=""
LAST_RENAME_OUTCOME="not-started"
BOUND_INSTALL_ROOT_IDENTITY=""
BOUND_BACKUP_ROOT_IDENTITY=""
BOUND_LOCK_IDENTITY=""
LAST_STAGED_IDENTITY=""
TRANSACTION_ROOT_FD=8
TRANSACTION_LOCK_FD=9
TRANSACTION_FDS_OPEN=false

bound_rename_parent_identity() {
  case "$1" in
    "$INSTALL_ROOT")
      echo "$BOUND_INSTALL_ROOT_IDENTITY"
      ;;
    "$BACKUP_ROOT")
      echo "$BOUND_BACKUP_ROOT_IDENTITY"
      ;;
    *)
      echo "Rename parent is outside the bound install topology: $1" >&2
      return 1
      ;;
  esac
}

exclusive_rename_bundle() {
  local source="$1"
  local destination="$2"
  local label="$3"
  local expected_manifest="$4"
  local expected_signature="$5"
  local metadata_policy="$6"
  local source_identity
  local helper_result
  local helper_status
  local source_parent
  local destination_parent
  local source_parent_identity
  local destination_parent_identity
  local current_parent_identity

  LAST_RENAME_SOURCE_IDENTITY=""
  LAST_RENAME_DESTINATION_IDENTITY=""
  LAST_RENAME_OUTCOME="not-started"
  if [[ ! "$expected_manifest" =~ ^[0-9a-f]{64}$ ]]; then
    echo "$label requires an exact 64-character source-state manifest." >&2
    LAST_RENAME_OUTCOME="unchanged"
    return 1
  fi
  case "$expected_signature" in
    valid | missing-or-invalid)
      ;;
    *)
      echo "$label requires an exact source signature state." >&2
      LAST_RENAME_OUTCOME="unchanged"
      return 1
      ;;
  esac
  case "$metadata_policy" in
    preserve | normalized)
      ;;
    *)
      echo "$label requires a supported manifest metadata policy." >&2
      LAST_RENAME_OUTCOME="unchanged"
      return 1
      ;;
  esac
  if ! assert_bound_transaction_lock "before $label"; then
    LAST_RENAME_OUTCOME="unchanged"
    return 1
  fi
  if [ -L "$source" ] || [ ! -d "$source" ]; then
    echo "$label source must be a physical directory: $source" >&2
    LAST_RENAME_OUTCOME="unchanged"
    return 1
  fi
  if ! source_identity="$(path_identity "$source")"; then
    echo "Could not read the source device/inode for $label: $source" >&2
    LAST_RENAME_OUTCOME="unchanged"
    return 1
  fi
  LAST_RENAME_SOURCE_IDENTITY="$source_identity"

  source_parent="$(/usr/bin/dirname "$source")"
  destination_parent="$(/usr/bin/dirname "$destination")"
  if ! source_parent_identity="$(bound_rename_parent_identity "$source_parent")" \
    || ! destination_parent_identity="$(bound_rename_parent_identity "$destination_parent")" \
    || [ -z "$source_parent_identity" ] \
    || [ -z "$destination_parent_identity" ]; then
    echo "Could not resolve bound parent identities for $label." >&2
    LAST_RENAME_OUTCOME="unchanged"
    return 1
  fi
  current_parent_identity="$(path_identity "$source_parent" || true)"
  if [ "$current_parent_identity" != "$source_parent_identity" ]; then
    echo "$label source parent changed after topology validation." >&2
    LAST_RENAME_OUTCOME="unchanged"
    return 1
  fi
  current_parent_identity="$(path_identity "$destination_parent" || true)"
  if [ "$current_parent_identity" != "$destination_parent_identity" ]; then
    echo "$label destination parent changed after topology validation." >&2
    LAST_RENAME_OUTCOME="unchanged"
    return 1
  fi

  if helper_result="$("$PYTHON_BIN" - \
    "$source" \
    "$destination" \
    "$source_parent_identity" \
    "$destination_parent_identity" \
    "$expected_manifest" \
    "$expected_signature" \
    "$metadata_policy" \
    "$SCRIPT_DIR/codex-install.sh" \
    "$INSTALL_ROOT" \
    "$TRANSACTION_ROOT_FD" \
    "$TRANSACTION_LOCK_FD" \
    "$(/usr/bin/basename "$LOCK_DIR")" \
    "$BOUND_INSTALL_ROOT_IDENTITY" \
    "$BOUND_LOCK_IDENTITY" \
    "$TEST_HOOK_ENABLED" \
    "$TEST_HOOK_POINT" \
    "$TEST_HOOK_DIR" <<'PY'
import ctypes
import os
import subprocess
import stat
import sys
import time

source = os.fsencode(sys.argv[1])
destination = os.fsencode(sys.argv[2])
expected_source_parent_identity = sys.argv[3]
expected_destination_parent_identity = sys.argv[4]
expected_manifest = sys.argv[5]
expected_signature = sys.argv[6]
metadata_policy = sys.argv[7]
installer_script = sys.argv[8]
install_root = os.fsencode(sys.argv[9])
transaction_root_fd = int(sys.argv[10])
transaction_lock_fd = int(sys.argv[11])
lock_name = os.fsencode(sys.argv[12])
expected_root_identity = sys.argv[13]
expected_lock_identity = sys.argv[14]
test_hook_enabled = sys.argv[15] == "true"
test_hook_point = sys.argv[16]
test_hook_directory = os.fsencode(sys.argv[17]) if sys.argv[17] else b""
source_parent = os.path.dirname(source)
destination_parent = os.path.dirname(destination)
source_name = os.path.basename(source)
destination_name = os.path.basename(destination)
libc = ctypes.CDLL(None, use_errno=True)
renameatx_np = libc.renameatx_np
renameatx_np.argtypes = [
    ctypes.c_int,
    ctypes.c_char_p,
    ctypes.c_int,
    ctypes.c_char_p,
    ctypes.c_uint,
]
renameatx_np.restype = ctypes.c_int

RENAME_EXCL = 0x00000004
OPEN_PARENT_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW


def identity(value):
    return f"{value.st_dev}:{value.st_ino}"


def parent_path_matches(path, expected):
    value = os.lstat(path)
    return stat.S_ISDIR(value.st_mode) and identity(value) == expected


def verify_transaction_lock(context):
    root_stat = os.fstat(transaction_root_fd)
    lock_stat = os.fstat(transaction_lock_fd)
    visible_root = os.lstat(install_root)
    visible_lock = os.stat(
        lock_name,
        dir_fd=transaction_root_fd,
        follow_symlinks=False,
    )
    if not stat.S_ISDIR(root_stat.st_mode) \
        or not stat.S_ISDIR(visible_root.st_mode) \
        or identity(root_stat) != expected_root_identity \
        or identity(visible_root) != expected_root_identity:
        raise RuntimeError(f"authoritative install root changed {context}")
    if not stat.S_ISDIR(lock_stat.st_mode) \
        or not stat.S_ISDIR(visible_lock.st_mode) \
        or identity(lock_stat) != expected_lock_identity \
        or identity(visible_lock) != expected_lock_identity:
        raise RuntimeError(f"authoritative install lock changed {context}")


def stat_at(parent_fd, name):
    return os.stat(name, dir_fd=parent_fd, follow_symlinks=False)


def source_is_absent(parent_fd, name):
    try:
        stat_at(parent_fd, name)
    except FileNotFoundError:
        return True
    return False


def path_is_absent(path):
    try:
        os.lstat(path)
    except FileNotFoundError:
        return True
    return False


def exclusive_rename(source_fd, source_basename, destination_fd, destination_basename):
    if renameatx_np(
        source_fd,
        source_basename,
        destination_fd,
        destination_basename,
        RENAME_EXCL,
    ) != 0:
        error_number = ctypes.get_errno()
        raise OSError(error_number, os.strerror(error_number))


def stable_bundle_state(parent_fd, basename):
    if b"/" in basename or basename in (b"", b".", b".."):
        raise RuntimeError("state snapshot bundle name is not a safe basename")
    environment = os.environ.copy()
    environment["MICAI_INTERNAL_STATE_HELPER"] = "1"
    environment["MICAI_INTERNAL_BUNDLE_BASENAME"] = os.fsdecode(basename)
    environment["MICAI_INTERNAL_METADATA_POLICY"] = metadata_policy
    environment.pop("MICAI_INSTALL_TEST_HOOK_POINT", None)
    environment.pop("MICAI_INSTALL_TEST_HOOK_DIR", None)

    def enter_parent():
        os.fchdir(parent_fd)

    result = subprocess.run(
        ["/bin/bash", installer_script, "--internal-bundle-state"],
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        pass_fds=(parent_fd,),
        preexec_fn=enter_parent,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", "replace").strip()
        raise RuntimeError(f"FD-anchored bundle-state snapshot failed: {detail}")
    output = result.stdout.decode("ascii", "strict").strip()
    pieces = output.split("|")
    if len(pieces) != 2:
        raise RuntimeError("FD-anchored bundle-state helper returned malformed output")
    manifest, signature = pieces
    if len(manifest) != 64 or any(character not in "0123456789abcdef" for character in manifest):
        raise RuntimeError("FD-anchored bundle-state helper returned an invalid manifest")
    if signature not in ("valid", "missing-or-invalid"):
        raise RuntimeError("FD-anchored bundle-state helper returned an invalid signature state")
    return manifest, signature


def verify_expected_bundle_state(parent_fd, basename, context):
    manifest, signature = stable_bundle_state(parent_fd, basename)
    if manifest != expected_manifest or signature != expected_signature:
        raise RuntimeError(
            f"{context} differs from the exact reviewed manifest/signature state"
        )


def run_post_kernel_test_hook():
    if not test_hook_enabled or test_hook_point != "inside-rename-after-kernel":
        return
    ready = os.path.join(test_hook_directory, b"inside-rename-after-kernel.ready")
    release = os.path.join(test_hook_directory, b"inside-rename-after-kernel.release")
    if os.path.lexists(ready) or os.path.lexists(release):
        raise RuntimeError("rename test hook marker is already occupied")
    os.mkdir(ready, 0o700)
    while not os.path.lexists(release):
        time.sleep(0.01)
    release_stat = os.lstat(release)
    if not stat.S_ISDIR(release_stat.st_mode):
        raise RuntimeError("rename test release marker is not a physical directory")


source_parent_fd = -1
destination_parent_fd = -1
renamed = False
source_stat = None
try:
    verify_transaction_lock("before opening rename parents")
    source_parent_fd = os.open(source_parent, OPEN_PARENT_FLAGS)
    destination_parent_fd = os.open(destination_parent, OPEN_PARENT_FLAGS)
    source_parent_before = os.fstat(source_parent_fd)
    destination_parent_before = os.fstat(destination_parent_fd)
    if identity(source_parent_before) != expected_source_parent_identity:
        raise RuntimeError("opened source parent differs from its bound identity")
    if identity(destination_parent_before) != expected_destination_parent_identity:
        raise RuntimeError("opened destination parent differs from its bound identity")
    if not parent_path_matches(source_parent, expected_source_parent_identity):
        raise RuntimeError("source parent path changed before exclusive rename")
    if not parent_path_matches(destination_parent, expected_destination_parent_identity):
        raise RuntimeError("destination parent path changed before exclusive rename")

    source_stat = stat_at(source_parent_fd, source_name)
    if not stat.S_ISDIR(source_stat.st_mode):
        raise RuntimeError("exclusive rename source is not a physical directory")
    verify_expected_bundle_state(
        source_parent_fd,
        source_name,
        "exclusive rename source",
    )
    verify_transaction_lock("immediately before exclusive rename")
    exclusive_rename(
        source_parent_fd,
        source_name,
        destination_parent_fd,
        destination_name,
    )
    renamed = True
    run_post_kernel_test_hook()

    destination_stat = stat_at(destination_parent_fd, destination_name)
    if not source_is_absent(source_parent_fd, source_name):
        raise RuntimeError("exclusive rename left its source entry present")
    if identity(source_stat) != identity(destination_stat):
        raise RuntimeError("exclusive rename destination identity differs from its source")
    verify_expected_bundle_state(
        destination_parent_fd,
        destination_name,
        "committed rename destination",
    )
    verify_transaction_lock("after exclusive rename state verification")
    if identity(os.fstat(source_parent_fd)) != expected_source_parent_identity:
        raise RuntimeError("source parent identity changed during exclusive rename")
    if identity(os.fstat(destination_parent_fd)) != expected_destination_parent_identity:
        raise RuntimeError("destination parent identity changed during exclusive rename")
    if not parent_path_matches(source_parent, expected_source_parent_identity):
        raise RuntimeError("source parent path changed during exclusive rename")
    if not parent_path_matches(destination_parent, expected_destination_parent_identity):
        raise RuntimeError("destination parent path changed during exclusive rename")
    destination_path_stat = os.lstat(destination)
    if identity(destination_path_stat) != identity(source_stat):
        raise RuntimeError("visible destination differs from the moved source identity")
    if not path_is_absent(source):
        raise RuntimeError("visible source path remains after exclusive rename")

    print(f"committed:{identity(destination_stat)}")
except (OSError, RuntimeError) as error:
    if renamed and source_stat is not None:
        try:
            destination_stat = stat_at(destination_parent_fd, destination_name)
            if (
                not source_is_absent(source_parent_fd, source_name)
                or identity(destination_stat) != identity(source_stat)
            ):
                raise RuntimeError("cannot prove the moved entry before kernel rollback")
            exclusive_rename(
                destination_parent_fd,
                destination_name,
                source_parent_fd,
                source_name,
            )
            restored_stat = stat_at(source_parent_fd, source_name)
            if identity(restored_stat) != identity(source_stat):
                raise RuntimeError("kernel rollback restored a different source identity")
            if not source_is_absent(destination_parent_fd, destination_name):
                raise RuntimeError("kernel rollback left the destination entry present")
            verify_expected_bundle_state(
                source_parent_fd,
                source_name,
                "kernel rollback restored source",
            )
            if not parent_path_matches(source_parent, expected_source_parent_identity):
                raise RuntimeError("kernel rollback source parent is no longer visible")
            if not parent_path_matches(
                destination_parent,
                expected_destination_parent_identity,
            ):
                raise RuntimeError(
                    "kernel rollback restored the source but a rename parent remains substituted"
                )
            visible_source = os.lstat(source)
            if identity(visible_source) != identity(source_stat):
                raise RuntimeError("visible rollback source differs from the moved identity")
            if not path_is_absent(destination):
                raise RuntimeError("visible rollback destination remains occupied")
            try:
                verify_transaction_lock("after kernel rollback")
                lock_note = ""
            except (OSError, RuntimeError) as lock_error:
                lock_note = f"; authoritative lock check also failed: {lock_error}"
            print(
                f"Exclusive rename post-check failed; kernel rollback restored the source: "
                f"{error}{lock_note}",
                file=sys.stderr,
            )
            sys.exit(10)
        except (OSError, RuntimeError) as rollback_error:
            print(
                f"Exclusive rename failed after moving and kernel rollback was incomplete: "
                f"{error}; {rollback_error}",
                file=sys.stderr,
            )
            sys.exit(20)
    print(f"State-bound kernel exclusive rename failed: {error}", file=sys.stderr)
    sys.exit(10)
finally:
    if destination_parent_fd >= 0:
        os.close(destination_parent_fd)
    if source_parent_fd >= 0:
        os.close(source_parent_fd)
PY
  )"; then
    helper_status=0
  else
    helper_status=$?
  fi

  case "$helper_status" in
    0)
      case "$helper_result" in
        committed:*)
          LAST_RENAME_DESTINATION_IDENTITY="${helper_result#committed:}"
          if [ "$LAST_RENAME_DESTINATION_IDENTITY" != "$source_identity" ]; then
            echo "$label helper reported a committed identity different from its source." >&2
            LAST_RENAME_OUTCOME="ambiguous"
            return 1
          fi
          LAST_RENAME_OUTCOME="committed"
          return 0
          ;;
        *)
          echo "$label helper returned an unsupported success result." >&2
          LAST_RENAME_OUTCOME="ambiguous"
          return 1
          ;;
      esac
      ;;
    10)
      LAST_RENAME_OUTCOME="unchanged"
      return 1
      ;;
    20)
      LAST_RENAME_OUTCOME="ambiguous"
      return 1
      ;;
    *)
      echo "$label helper exited unexpectedly with status $helper_status." >&2
      LAST_RENAME_OUTCOME="ambiguous"
      return 1
      ;;
  esac
}

PLIST_VALUE=""

read_plist_value() {
  local bundle="$1"
  local key="$2"
  local marker=$'\036'
  local captured

  PLIST_VALUE=""
  if ! captured="$("$PYTHON_BIN" - \
    "$bundle/Contents/Info.plist" \
    "$key" <<'PY'
import plistlib
import sys

plist_path = sys.argv[1]
key = sys.argv[2]

try:
    with open(plist_path, "rb") as plist_file:
        plist = plistlib.load(plist_file)
    value = plist[key]
    if isinstance(value, str):
        rendered = value
    elif value is True:
        rendered = "true"
    elif value is False:
        rendered = "false"
    elif isinstance(value, (int, float)):
        rendered = str(value)
    else:
        raise TypeError("unsupported plist value type")
    if "\x00" in rendered:
        raise ValueError("plist string contains a null byte")
    encoded = rendered.encode("utf-8")
except Exception:
    sys.exit(1)

sys.stdout.buffer.write(encoded)
sys.stdout.buffer.write(b"\x1e")
PY
  )"; then
    return 1
  fi
  case "$captured" in
    *"$marker")
      PLIST_VALUE="${captured%$marker}"
      ;;
    *)
      echo "Lossless plist reader returned malformed output for $key." >&2
      return 1
      ;;
  esac
}

validate_plist_basename() {
  local value="$1"
  local key="$2"
  local kind="$3"
  local stem

  case "$value" in
    "" | "." | ".." | .* | */* | *$'\n'* | *$'\r'*)
      echo "Unsafe $key component: expected a nonhidden single basename." >&2
      return 1
      ;;
  esac

  if [ "$kind" = "icon" ]; then
    case "$value" in
      *.icns)
        stem="${value%.icns}"
        if [ -z "$stem" ]; then
          echo "Unsafe $key component: the .icns basename is empty." >&2
          return 1
        fi
        ;;
      *.*)
        echo "Unsafe $key component: only an optional .icns extension is supported." >&2
        return 1
        ;;
    esac
  fi
}

bundle_executable_path() {
  local executable
  if read_plist_value "$1" CFBundleExecutable; then
    executable="$PLIST_VALUE"
    validate_plist_basename "$executable" "CFBundleExecutable" executable || return 1
  else
    executable="MicAI"
  fi
  printf '%s\n' "$1/Contents/MacOS/$executable"
}

bundle_icon_path() {
  local icon_file
  if read_plist_value "$1" CFBundleIconFile; then
    icon_file="$PLIST_VALUE"
    validate_plist_basename "$icon_file" "CFBundleIconFile" icon || return 1
  else
    icon_file="MicAI"
  fi
  if [[ "$icon_file" == *.icns ]]; then
    printf '%s\n' "$1/Contents/Resources/$icon_file"
  else
    printf '%s\n' "$1/Contents/Resources/$icon_file.icns"
  fi
}

validate_bundle_path_semantics() {
  local bundle="$1"
  local label="$2"
  local plist="$bundle/Contents/Info.plist"
  local executable
  local icon
  local directory
  local file

  if ! path_exists "$bundle"; then
    return 0
  fi
  if ! require_physical_directory "$bundle" "$label"; then
    return 1
  fi

  for directory in \
    "$bundle/Contents" \
    "$bundle/Contents/MacOS" \
    "$bundle/Contents/Resources";
  do
    if path_exists "$directory" \
      && ! require_physical_directory "$directory" "$label component"; then
      return 1
    fi
  done

  if [ -L "$plist" ]; then
    echo "$label Info.plist must not be a symbolic link: $plist" >&2
    return 1
  fi
  if path_exists "$plist" && [ ! -f "$plist" ]; then
    echo "$label Info.plist must be a regular file: $plist" >&2
    return 1
  fi
  executable="$(bundle_executable_path "$bundle")" || return 1
  icon="$(bundle_icon_path "$bundle")" || return 1
  for file in "$executable" "$icon"; do
    if [ -L "$file" ]; then
      echo "$label file must not be a symbolic link: $file" >&2
      return 1
    fi
    if path_exists "$file" && [ ! -f "$file" ]; then
      echo "$label file must be a regular file: $file" >&2
      return 1
    fi
  done
}

require_plist_value() {
  local bundle="$1"
  local key="$2"
  local expected="$3"
  local actual
  if read_plist_value "$bundle" "$key"; then
    actual="$PLIST_VALUE"
  else
    actual=""
  fi
  if [ "$actual" != "$expected" ]; then
    echo "Invalid $key in $bundle: expected '$expected', found '${actual:-<missing>}'." >&2
    return 1
  fi
}

validate_installable_bundle() {
  local bundle="$1"
  local plist="$bundle/Contents/Info.plist"
  local executable="$bundle/Contents/MacOS/MicAI"
  local icon="$bundle/Contents/Resources/MicAI.icns"
  local manifest_before
  local manifest_after

  if ! path_exists "$bundle"; then
    echo "Missing app bundle: $bundle" >&2
    return 1
  fi
  validate_bundle_path_semantics "$bundle" "App bundle" || return 1
  require_physical_directory "$bundle/Contents" "App bundle Contents" || return 1
  require_physical_directory "$bundle/Contents/MacOS" "App bundle MacOS" || return 1
  require_physical_directory "$bundle/Contents/Resources" "App bundle Resources" || return 1
  if [ -L "$plist" ] || [ ! -f "$plist" ]; then
    echo "Info.plist must be a physical file: $plist" >&2
    return 1
  fi
  if ! /usr/bin/plutil -lint "$plist" >/dev/null 2>&1; then
    echo "Invalid or missing plist: $plist" >&2
    return 1
  fi
  require_plist_value "$bundle" CFBundleIdentifier "com.mileschu.micai" || return 1
  require_plist_value "$bundle" CFBundleExecutable "MicAI" || return 1
  require_plist_value "$bundle" CFBundleIconFile "MicAI" || return 1
  require_plist_value "$bundle" CFBundlePackageType "APPL" || return 1
  require_plist_value "$bundle" LSMinimumSystemVersion "14.0" || return 1
  require_plist_value "$bundle" LSUIElement "true" || return 1
  if [ -L "$executable" ] || [ ! -x "$executable" ]; then
    echo "Missing executable: $executable" >&2
    return 1
  fi
  if [ -L "$icon" ] || [ ! -s "$icon" ]; then
    echo "Missing app icon: $icon" >&2
    return 1
  fi
  if ! manifest_before="$(bundle_manifest_sha256 "$bundle" normalized)"; then
    echo "The installable bundle does not satisfy the normalized metadata contract: $bundle" >&2
    return 1
  fi
  if ! /usr/bin/codesign --verify --deep --strict "$bundle" >/dev/null 2>&1; then
    echo "Invalid code signature: $bundle" >&2
    return 1
  fi
  if ! manifest_after="$(bundle_manifest_sha256 "$bundle" normalized)" \
    || [ "$manifest_before" != "$manifest_after" ]; then
    echo "The bundle changed while its code signature was being verified: $bundle" >&2
    return 1
  fi
}

bundle_report() {
  local label="$1"
  local bundle="$2"
  local plist="$bundle/Contents/Info.plist"
  local executable
  local icon
  local icon_metadata
  local identifier
  local manifest

  executable="$(bundle_executable_path "$bundle")" || return 1
  icon="$(bundle_icon_path "$bundle")" || return 1
  if read_plist_value "$bundle" CFBundleIconFile; then
    icon_metadata="$PLIST_VALUE"
  else
    icon_metadata=""
  fi
  if read_plist_value "$bundle" CFBundleIdentifier; then
    identifier="$PLIST_VALUE"
  else
    identifier="<missing>"
  fi
  manifest="$(bundle_manifest_or_missing "$bundle")"

  echo "$label"
  echo "  Path: $bundle"
  if path_exists "$bundle"; then
    echo "  Bundle present: yes"
  else
    echo "  Bundle present: no"
  fi
  if /usr/bin/plutil -lint "$plist" >/dev/null 2>&1; then
    echo "  Info.plist: valid"
  else
    echo "  Info.plist: missing or invalid"
  fi
  echo "  CFBundleIdentifier: $identifier"
  echo "  CFBundleIconFile: ${icon_metadata:-<missing>}"
  if [ -s "$icon" ]; then
    echo "  Icon resource: present ($icon)"
  else
    echo "  Icon resource: missing ($icon)"
  fi
  if /usr/bin/codesign --verify --deep --strict "$bundle" >/dev/null 2>&1; then
    echo "  Signature: valid"
  else
    echo "  Signature: missing or invalid"
  fi
  echo "  Executable SHA-256: $(hash_or_missing "$executable")"
  echo "  Icon SHA-256: $(hash_or_missing "$icon")"
  echo "  Info.plist SHA-256: $(hash_or_missing "$plist")"
  echo "  Full bundle-state manifest SHA-256: $manifest"
}

expected_source_state_matches() {
  local bundle="$1"
  local executable="$bundle/Contents/MacOS/MicAI"
  local icon="$bundle/Contents/Resources/MicAI.icns"
  local plist="$bundle/Contents/Info.plist"
  local manifest_before
  local manifest_after
  local executable_hash
  local icon_hash
  local plist_hash

  manifest_before="$(bundle_manifest_sha256 "$bundle" normalized)" || return 1
  executable_hash="$(sha256_file "$executable")" || return 1
  icon_hash="$(sha256_file "$icon")" || return 1
  plist_hash="$(sha256_file "$plist")" || return 1
  if ! /usr/bin/codesign --verify --deep --strict "$bundle" >/dev/null 2>&1; then
    echo "Source-state signature mismatch: $bundle" >&2
    return 1
  fi
  manifest_after="$(bundle_manifest_sha256 "$bundle" normalized)" || return 1

  if [ "$manifest_before" != "$manifest_after" ]; then
    echo "Source-state manifest changed during verification: $bundle" >&2
    return 1
  fi
  if [ "$manifest_after" != "$MICAI_EXPECTED_BUNDLE_MANIFEST_SHA256" ]; then
    echo "Source-state full manifest differs from the reviewed value: $bundle" >&2
    return 1
  fi
  if [ "$executable_hash" != "$MICAI_EXPECTED_EXECUTABLE_SHA256" ]; then
    echo "Source-state executable hash differs from the reviewed value: $bundle" >&2
    return 1
  fi
  if [ "$icon_hash" != "$MICAI_EXPECTED_ICON_SHA256" ]; then
    echo "Source-state icon hash differs from the reviewed value: $bundle" >&2
    return 1
  fi
  if [ "$plist_hash" != "$MICAI_EXPECTED_PLIST_SHA256" ]; then
    echo "Source-state Info.plist hash differs from the reviewed value: $bundle" >&2
    return 1
  fi
}

signature_state() {
  if /usr/bin/codesign --verify --deep --strict "$1" >/dev/null 2>&1; then
    echo "valid"
  else
    echo "missing-or-invalid"
  fi
}

capture_bundle_state_for_rename() {
  local bundle="$1"
  local metadata_policy="$2"
  local manifest_before
  local manifest_after
  local signature

  manifest_before="$(bundle_manifest_sha256 "$bundle" "$metadata_policy")" || return 1
  signature="$(signature_state "$bundle")" || return 1
  manifest_after="$(bundle_manifest_sha256 "$bundle" "$metadata_policy")" || return 1
  if [ "$manifest_before" != "$manifest_after" ]; then
    echo "Bundle state changed while preparing an exact rename guard: $bundle" >&2
    return 1
  fi
  printf '%s|%s\n' "$manifest_after" "$signature"
}

reviewed_target_state_matches_at() {
  local bundle="$1"
  local present="no"
  local executable
  local icon
  local plist="$bundle/Contents/Info.plist"
  local manifest_before
  local manifest_after
  local executable_hash
  local icon_hash
  local plist_hash
  local signature

  if path_exists "$bundle"; then
    present="yes"
  fi
  if [ "$present" != "$MICAI_EXPECTED_TARGET_PRESENT" ]; then
    return 1
  fi
  if [ "$present" = "no" ]; then
    [ "$MICAI_EXPECTED_TARGET_EXECUTABLE_SHA256" = "<missing>" ] \
      && [ "$MICAI_EXPECTED_TARGET_ICON_SHA256" = "<missing>" ] \
      && [ "$MICAI_EXPECTED_TARGET_PLIST_SHA256" = "<missing>" ] \
      && [ "$MICAI_EXPECTED_TARGET_BUNDLE_MANIFEST_SHA256" = "<missing>" ] \
      && [ "$MICAI_EXPECTED_TARGET_SIGNATURE" = "missing-or-invalid" ]
    return
  fi

  validate_bundle_path_semantics "$bundle" "Reviewed target" || return 1
  executable="$(bundle_executable_path "$bundle")" || return 1
  icon="$(bundle_icon_path "$bundle")" || return 1
  manifest_before="$(bundle_manifest_sha256 "$bundle" preserve reviewed-target)" || return 1
  executable_hash="$(hash_or_missing "$executable")" || return 1
  icon_hash="$(hash_or_missing "$icon")" || return 1
  plist_hash="$(hash_or_missing "$plist")" || return 1
  signature="$(signature_state "$bundle")" || return 1
  manifest_after="$(bundle_manifest_sha256 "$bundle" preserve)" || return 1

  [ "$manifest_before" = "$manifest_after" ] \
    && [ "$manifest_after" = "$MICAI_EXPECTED_TARGET_BUNDLE_MANIFEST_SHA256" ] \
    && [ "$executable_hash" = "$MICAI_EXPECTED_TARGET_EXECUTABLE_SHA256" ] \
    && [ "$icon_hash" = "$MICAI_EXPECTED_TARGET_ICON_SHA256" ] \
    && [ "$plist_hash" = "$MICAI_EXPECTED_TARGET_PLIST_SHA256" ] \
    && [ "$signature" = "$MICAI_EXPECTED_TARGET_SIGNATURE" ]
}

current_target_state_matches() {
  reviewed_target_state_matches_at "$TARGET_APP"
}

validate_install_root_if_present() {
  if path_exists "$INSTALL_ROOT"; then
    require_physical_directory "$INSTALL_ROOT" "Install root" || return 1
  fi
}

assert_bound_install_root() {
  local current_identity

  require_physical_directory "$INSTALL_ROOT" "Bound install root" || return 1
  current_identity="$(path_identity "$INSTALL_ROOT" || true)"
  if [ -z "$BOUND_INSTALL_ROOT_IDENTITY" ] \
    || [ "$current_identity" != "$BOUND_INSTALL_ROOT_IDENTITY" ]; then
    echo "The install-root directory changed after it was bound." >&2
    echo "  Expected: ${BOUND_INSTALL_ROOT_IDENTITY:-<unbound>}" >&2
    echo "  Current: ${current_identity:-<missing-or-unsupported>}" >&2
    return 1
  fi
}

close_transaction_fds() {
  if [ "$TRANSACTION_FDS_OPEN" = true ]; then
    exec 9<&-
    exec 8<&-
    TRANSACTION_FDS_OPEN=false
  fi
}

assert_bound_transaction_lock() {
  local checkpoint="${1:-during the apply transaction}"

  if [ "$LOCK_HELD" != true ] || [ "$TRANSACTION_FDS_OPEN" != true ]; then
    echo "The authoritative install transaction descriptors are not open $checkpoint." >&2
    return 1
  fi

  if ! "$PYTHON_BIN" - \
    "$TRANSACTION_ROOT_FD" \
    "$TRANSACTION_LOCK_FD" \
    "$INSTALL_ROOT" \
    "$(/usr/bin/basename "$LOCK_DIR")" \
    "$BOUND_INSTALL_ROOT_IDENTITY" \
    "$BOUND_LOCK_IDENTITY" \
    "$checkpoint" <<'PY'
import os
import stat
import sys

root_fd = int(sys.argv[1])
lock_fd = int(sys.argv[2])
root_path = os.fsencode(sys.argv[3])
lock_name = os.fsencode(sys.argv[4])
expected_root_identity = sys.argv[5]
expected_lock_identity = sys.argv[6]
checkpoint = sys.argv[7]


def identity(value):
    return f"{value.st_dev}:{value.st_ino}"


try:
    root_stat = os.fstat(root_fd)
    lock_stat = os.fstat(lock_fd)
    visible_root = os.lstat(root_path)
    visible_lock = os.stat(lock_name, dir_fd=root_fd, follow_symlinks=False)
    if not stat.S_ISDIR(root_stat.st_mode) or not stat.S_ISDIR(visible_root.st_mode):
        raise RuntimeError("install root is no longer a physical directory")
    if identity(root_stat) != expected_root_identity \
        or identity(visible_root) != expected_root_identity:
        raise RuntimeError("visible install root differs from the held root descriptor")
    if not stat.S_ISDIR(lock_stat.st_mode) or not stat.S_ISDIR(visible_lock.st_mode):
        raise RuntimeError("install lock is no longer a physical directory")
    if identity(lock_stat) != expected_lock_identity \
        or identity(visible_lock) != expected_lock_identity:
        raise RuntimeError("visible install lock differs from the held lock descriptor")
except (OSError, RuntimeError) as error:
    print(f"Authoritative install lock check failed {checkpoint}: {error}", file=sys.stderr)
    sys.exit(1)
PY
  then
    return 1
  fi
}

open_transaction_fds() {
  if ! exec 8< "$INSTALL_ROOT"; then
    echo "Could not retain an authoritative descriptor for the install root." >&2
    return 1
  fi
  if ! exec 9< "$LOCK_DIR"; then
    exec 8<&-
    echo "Could not retain an authoritative descriptor for the install lock." >&2
    return 1
  fi
  TRANSACTION_FDS_OPEN=true
  if ! assert_bound_transaction_lock "while opening the transaction"; then
    close_transaction_fds
    return 1
  fi
}

assert_bound_backup_root() {
  local current_identity

  require_physical_directory "$BACKUP_ROOT" "Bound backup root" || return 1
  current_identity="$(path_identity "$BACKUP_ROOT" || true)"
  if [ -z "$BOUND_BACKUP_ROOT_IDENTITY" ] \
    || [ "$current_identity" != "$BOUND_BACKUP_ROOT_IDENTITY" ]; then
    echo "The backup-root directory changed after it was bound." >&2
    echo "  Expected: ${BOUND_BACKUP_ROOT_IDENTITY:-<unbound>}" >&2
    echo "  Current: ${current_identity:-<missing-or-unsupported>}" >&2
    return 1
  fi
}

validate_backup_root_if_present() {
  if path_exists "$BACKUP_ROOT"; then
    require_physical_directory "$BACKUP_ROOT" "Backup root" || return 1
    require_same_device "$INSTALL_ROOT" "$BACKUP_ROOT" "Backup root" || return 1
  fi
}

validate_reviewed_target_path() {
  if path_exists "$TARGET_APP"; then
    validate_bundle_path_semantics "$TARGET_APP" "Installed target" || return 1
    require_same_device "$INSTALL_ROOT" "$TARGET_APP" "Installed target" || return 1
  fi
}

validate_reserved_paths_absent() {
  local reserved_path

  for reserved_path in "$STAGED_APP" "$BACKUP_APP" "$FAILED_APP"; do
    if path_exists "$reserved_path"; then
      echo "Reserved install path is occupied or a symbolic link: $reserved_path" >&2
      return 1
    fi
  done
}

validate_plan_path_semantics() {
  validate_install_root_if_present || return 1
  if path_exists "$INSTALL_ROOT"; then
    validate_backup_root_if_present || return 1
    validate_reviewed_target_path || return 1
  fi
  validate_reserved_paths_absent || return 1
}

captured_plan_state_matches() {
  local source_before
  local source_after
  local target_before
  local target_after
  local target_signature
  local install_root_present="no"
  local install_root_identity="<missing>"

  source_before="$(bundle_manifest_sha256 "$SOURCE_APP" normalized)" || return 1
  [ "$(sha256_file "$SOURCE_EXECUTABLE")" = "$SOURCE_EXECUTABLE_SHA256" ] || return 1
  [ "$(sha256_file "$SOURCE_ICON")" = "$SOURCE_ICON_SHA256" ] || return 1
  [ "$(sha256_file "$SOURCE_PLIST")" = "$SOURCE_PLIST_SHA256" ] || return 1
  /usr/bin/codesign --verify --deep --strict "$SOURCE_APP" >/dev/null 2>&1 || return 1
  source_after="$(bundle_manifest_sha256 "$SOURCE_APP" normalized)" || return 1
  [ "$source_before" = "$source_after" ] || return 1
  [ "$source_after" = "$SOURCE_BUNDLE_MANIFEST_SHA256" ] || return 1

  target_before="$(bundle_manifest_or_missing "$TARGET_APP")" || return 1
  [ "$(hash_or_missing "$TARGET_EXECUTABLE")" = "$TARGET_EXECUTABLE_SHA256" ] || return 1
  [ "$(hash_or_missing "$TARGET_ICON")" = "$TARGET_ICON_SHA256" ] || return 1
  [ "$(hash_or_missing "$TARGET_PLIST")" = "$TARGET_PLIST_SHA256" ] || return 1
  target_signature="$(signature_state "$TARGET_APP")" || return 1
  target_after="$(bundle_manifest_or_missing "$TARGET_APP")" || return 1
  [ "$target_before" = "$target_after" ] || return 1
  [ "$target_after" = "$TARGET_BUNDLE_MANIFEST_SHA256" ] || return 1
  [ "$target_signature" = "$TARGET_SIGNATURE" ] || return 1

  if path_exists "$INSTALL_ROOT"; then
    install_root_present="yes"
    install_root_identity="$(path_identity "$INSTALL_ROOT" || true)"
  fi
  [ "$install_root_present" = "$INSTALL_ROOT_PRESENT" ] \
    && [ "$install_root_identity" = "$INSTALL_ROOT_IDENTITY" ]
}

prepare_install_root_for_apply() {
  local parent
  local current_identity

  if [ "$MICAI_EXPECTED_INSTALL_ROOT_PRESENT" = "yes" ]; then
    if ! path_exists "$INSTALL_ROOT"; then
      echo "The reviewed install root is now missing: $INSTALL_ROOT" >&2
      return 1
    fi
    require_physical_directory "$INSTALL_ROOT" "Install root" || return 1
    current_identity="$(path_identity "$INSTALL_ROOT" || true)"
    if [ "$current_identity" != "$MICAI_EXPECTED_INSTALL_ROOT_IDENTITY" ]; then
      echo "The install-root device/inode differs from the reviewed plan." >&2
      echo "  Expected: $MICAI_EXPECTED_INSTALL_ROOT_IDENTITY" >&2
      echo "  Current: ${current_identity:-<missing-or-unsupported>}" >&2
      return 1
    fi
    BOUND_INSTALL_ROOT_IDENTITY="$current_identity"
    return 0
  fi

  if [ "$MICAI_EXPECTED_INSTALL_ROOT_PRESENT" != "no" ] \
    || [ "$MICAI_EXPECTED_INSTALL_ROOT_IDENTITY" != "<missing>" ]; then
    echo "The reviewed install-root state is invalid." >&2
    return 1
  fi
  if path_exists "$INSTALL_ROOT"; then
    echo "The install root appeared after the reviewed plan: $INSTALL_ROOT" >&2
    return 1
  fi

  parent="$(/usr/bin/dirname "$INSTALL_ROOT")"
  require_physical_directory "$parent" "Install-root parent" || return 1
  if ! /bin/mkdir "$INSTALL_ROOT"; then
    echo "Could not atomically create the physical install root: $INSTALL_ROOT" >&2
    return 1
  fi
  require_physical_directory "$INSTALL_ROOT" "Install root" || return 1
  BOUND_INSTALL_ROOT_IDENTITY="$(path_identity "$INSTALL_ROOT")" || return 1
}

acquire_apply_lock() {
  local result

  if ! result="$("$PYTHON_BIN" - \
    "$INSTALL_ROOT" "$BOUND_INSTALL_ROOT_IDENTITY" "$(/usr/bin/basename "$LOCK_DIR")" <<'PY'
import errno
import os
import stat
import sys

root_path = os.fsencode(sys.argv[1])
expected_root_identity = sys.argv[2]
lock_name = os.fsencode(sys.argv[3])
OPEN_DIRECTORY = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW


def identity(value):
    return f"{value.st_dev}:{value.st_ino}"


root_fd = -1
lock_fd = -1
created = False
try:
    if b"/" in lock_name or lock_name in (b"", b".", b".."):
        raise RuntimeError("invalid lock basename")
    root_before = os.lstat(root_path)
    root_fd = os.open(root_path, OPEN_DIRECTORY)
    opened_root = os.fstat(root_fd)
    if not stat.S_ISDIR(root_before.st_mode):
        raise RuntimeError("install root is not a physical directory")
    if identity(root_before) != expected_root_identity \
        or identity(opened_root) != expected_root_identity:
        raise RuntimeError("install root differs from its reviewed identity")
    os.mkdir(lock_name, 0o700, dir_fd=root_fd)
    created = True
    lock_fd = os.open(lock_name, OPEN_DIRECTORY, dir_fd=root_fd)
    lock_stat = os.fstat(lock_fd)
    if not stat.S_ISDIR(lock_stat.st_mode):
        raise RuntimeError("install lock is not a physical directory")
    if identity(os.fstat(root_fd)) != expected_root_identity \
        or identity(os.lstat(root_path)) != expected_root_identity:
        raise RuntimeError("install root changed while acquiring the lock")
    visible_lock = os.stat(lock_name, dir_fd=root_fd, follow_symlinks=False)
    if identity(visible_lock) != identity(lock_stat):
        raise RuntimeError("install lock identity changed while acquiring it")
    print(f"{identity(opened_root)}|{identity(lock_stat)}")
except (FileExistsError, OSError, RuntimeError) as error:
    if created and root_fd >= 0:
        try:
            visible_lock = os.stat(lock_name, dir_fd=root_fd, follow_symlinks=False)
            if lock_fd >= 0 and identity(visible_lock) == identity(os.fstat(lock_fd)):
                os.rmdir(lock_name, dir_fd=root_fd)
        except OSError:
            pass
    if isinstance(error, FileExistsError) or getattr(error, "errno", None) == errno.EEXIST:
        print("Another MicAI install is active or left an ambiguous lock.", file=sys.stderr)
    else:
        print(f"Could not acquire the FD-anchored MicAI install lock: {error}", file=sys.stderr)
    sys.exit(1)
finally:
    if lock_fd >= 0:
        os.close(lock_fd)
    if root_fd >= 0:
        os.close(root_fd)
PY
  )"; then
    echo "The installer will not delete an existing or ambiguous lock: $LOCK_DIR" >&2
    return 1
  fi

  BOUND_INSTALL_ROOT_IDENTITY="${result%%|*}"
  BOUND_LOCK_IDENTITY="${result#*|}"
  if [ -z "$BOUND_INSTALL_ROOT_IDENTITY" ] \
    || [ -z "$BOUND_LOCK_IDENTITY" ] \
    || [ "$BOUND_INSTALL_ROOT_IDENTITY" = "$BOUND_LOCK_IDENTITY" ]; then
    echo "The FD-anchored install lock returned invalid identities." >&2
    return 1
  fi
  LOCK_HELD=true
  if ! open_transaction_fds; then
    echo "The acquired lock could not be retained as an authoritative transaction." >&2
    if ! release_apply_lock; then
      echo "The exact acquired lock is retained for inspection: $LOCK_DIR" >&2
    fi
    return 1
  fi
}

prepare_backup_root_for_apply() {
  local result

  assert_bound_transaction_lock "before backup-root preparation" || return 1
  if ! result="$("$PYTHON_BIN" - \
    "$INSTALL_ROOT" \
    "$BOUND_INSTALL_ROOT_IDENTITY" \
    "$(/usr/bin/basename "$BACKUP_ROOT")" \
    "$TRANSACTION_ROOT_FD" \
    "$TRANSACTION_LOCK_FD" \
    "$(/usr/bin/basename "$LOCK_DIR")" \
    "$BOUND_LOCK_IDENTITY" <<'PY'
import os
import stat
import sys

root_path = os.fsencode(sys.argv[1])
expected_root_identity = sys.argv[2]
backup_name = os.fsencode(sys.argv[3])
root_fd = int(sys.argv[4])
lock_fd = int(sys.argv[5])
lock_name = os.fsencode(sys.argv[6])
expected_lock_identity = sys.argv[7]
OPEN_DIRECTORY = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW


def identity(value):
    return f"{value.st_dev}:{value.st_ino}"


backup_fd = -1


def verify_transaction_lock(context):
    root_stat = os.fstat(root_fd)
    lock_stat = os.fstat(lock_fd)
    visible_root = os.lstat(root_path)
    visible_lock = os.stat(lock_name, dir_fd=root_fd, follow_symlinks=False)
    if not stat.S_ISDIR(root_stat.st_mode) \
        or not stat.S_ISDIR(visible_root.st_mode) \
        or identity(root_stat) != expected_root_identity \
        or identity(visible_root) != expected_root_identity:
        raise RuntimeError(f"install root changed {context}")
    if not stat.S_ISDIR(lock_stat.st_mode) \
        or not stat.S_ISDIR(visible_lock.st_mode) \
        or identity(lock_stat) != expected_lock_identity \
        or identity(visible_lock) != expected_lock_identity:
        raise RuntimeError(f"install lock changed {context}")


try:
    if b"/" in backup_name or backup_name in (b"", b".", b".."):
        raise RuntimeError("invalid backup-root basename")
    verify_transaction_lock("before backup-root preparation")
    root_stat = os.fstat(root_fd)
    try:
        os.mkdir(backup_name, 0o700, dir_fd=root_fd)
    except FileExistsError:
        pass
    verify_transaction_lock("after backup-root creation")
    backup_fd = os.open(backup_name, OPEN_DIRECTORY, dir_fd=root_fd)
    backup_stat = os.fstat(backup_fd)
    if not stat.S_ISDIR(backup_stat.st_mode):
        raise RuntimeError("backup root is not a physical directory")
    if backup_stat.st_dev != root_stat.st_dev:
        raise RuntimeError("backup root is not on the install-root device")
    verify_transaction_lock("after backup-root preparation")
    visible_backup = os.stat(backup_name, dir_fd=root_fd, follow_symlinks=False)
    if identity(visible_backup) != identity(backup_stat):
        raise RuntimeError("backup root identity changed during preparation")
    print(identity(backup_stat))
except (OSError, RuntimeError) as error:
    print(f"Could not prepare the FD-anchored backup root: {error}", file=sys.stderr)
    sys.exit(1)
finally:
    if backup_fd >= 0:
        os.close(backup_fd)
PY
  )"; then
    return 1
  fi
  BOUND_BACKUP_ROOT_IDENTITY="$result"
  assert_bound_transaction_lock "after backup-root preparation" || return 1
  assert_bound_backup_root || return 1
  require_same_device "$INSTALL_ROOT" "$BACKUP_ROOT" "Backup root" || return 1
}

prepare_staged_bundle() {
  local staged_identity

  assert_bound_transaction_lock "before staged-bundle preparation" || return 1
  if ! staged_identity="$("$PYTHON_BIN" - \
    "$SOURCE_APP" \
    "$INSTALL_ROOT" \
    "$BOUND_INSTALL_ROOT_IDENTITY" \
    "$(/usr/bin/basename "$STAGED_APP")" \
    "$TRANSACTION_ROOT_FD" \
    "$TRANSACTION_LOCK_FD" \
    "$(/usr/bin/basename "$LOCK_DIR")" \
    "$BOUND_LOCK_IDENTITY" <<'PY'
import os
import stat
import sys

source_path = os.fsencode(sys.argv[1])
root_path = os.fsencode(sys.argv[2])
expected_root_identity = sys.argv[3]
stage_name = os.fsencode(sys.argv[4])
root_fd = int(sys.argv[5])
lock_fd = int(sys.argv[6])
lock_name = os.fsencode(sys.argv[7])
expected_lock_identity = sys.argv[8]
OPEN_DIRECTORY = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
OPEN_FILE = os.O_RDONLY | os.O_NOFOLLOW


def identity(value):
    return f"{value.st_dev}:{value.st_ino}"


def stable_identity(value):
    return (
        value.st_dev,
        value.st_ino,
        value.st_mode,
        value.st_nlink,
        value.st_uid,
        value.st_gid,
        value.st_size,
        value.st_mtime_ns,
        value.st_ctime_ns,
        getattr(value, "st_flags", 0),
    )


def verify_transaction_lock(context):
    root_stat = os.fstat(root_fd)
    lock_stat = os.fstat(lock_fd)
    visible_root = os.lstat(root_path)
    visible_lock = os.stat(lock_name, dir_fd=root_fd, follow_symlinks=False)
    if not stat.S_ISDIR(root_stat.st_mode) \
        or not stat.S_ISDIR(visible_root.st_mode) \
        or identity(root_stat) != expected_root_identity \
        or identity(visible_root) != expected_root_identity:
        raise RuntimeError(f"install root changed {context}")
    if not stat.S_ISDIR(lock_stat.st_mode) \
        or not stat.S_ISDIR(visible_lock.st_mode) \
        or identity(lock_stat) != expected_lock_identity \
        or identity(visible_lock) != expected_lock_identity:
        raise RuntimeError(f"install lock changed {context}")


def copy_directory(source_fd, destination_fd):
    source_before = os.fstat(source_fd)
    names = sorted(os.fsencode(name) for name in os.listdir(source_fd))
    for name in names:
        verify_transaction_lock(f"before copying staged entry {os.fsdecode(name)}")
        source_entry = os.stat(name, dir_fd=source_fd, follow_symlinks=False)
        mode = stat.S_IMODE(source_entry.st_mode)
        if stat.S_ISDIR(source_entry.st_mode):
            child_source = os.open(name, OPEN_DIRECTORY, dir_fd=source_fd)
            child_destination = -1
            try:
                if stable_identity(os.fstat(child_source)) != stable_identity(source_entry):
                    raise RuntimeError(f"source directory changed while opening: {os.fsdecode(name)}")
                os.mkdir(name, 0o700, dir_fd=destination_fd)
                child_destination = os.open(name, OPEN_DIRECTORY, dir_fd=destination_fd)
                copy_directory(child_source, child_destination)
                os.fchmod(child_destination, mode)
                os.fchown(
                    child_destination,
                    source_entry.st_uid,
                    source_entry.st_gid,
                )
            finally:
                if child_destination >= 0:
                    os.close(child_destination)
                os.close(child_source)
        elif stat.S_ISREG(source_entry.st_mode):
            if source_entry.st_nlink != 1:
                raise RuntimeError(f"source regular file is hard linked: {os.fsdecode(name)}")
            child_source = os.open(name, OPEN_FILE, dir_fd=source_fd)
            child_destination = -1
            try:
                opened_before = os.fstat(child_source)
                if stable_identity(opened_before) != stable_identity(source_entry):
                    raise RuntimeError(f"source file changed while opening: {os.fsdecode(name)}")
                child_destination = os.open(
                    name,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                    0o600,
                    dir_fd=destination_fd,
                )
                while True:
                    chunk = os.read(child_source, 1024 * 1024)
                    if not chunk:
                        break
                    view = memoryview(chunk)
                    while view:
                        written = os.write(child_destination, view)
                        view = view[written:]
                os.fchmod(child_destination, mode)
                os.fchown(
                    child_destination,
                    opened_before.st_uid,
                    opened_before.st_gid,
                )
                if stable_identity(opened_before) != stable_identity(os.fstat(child_source)):
                    raise RuntimeError(f"source file changed while copying: {os.fsdecode(name)}")
            finally:
                if child_destination >= 0:
                    os.close(child_destination)
                os.close(child_source)
        elif stat.S_ISLNK(source_entry.st_mode):
            if source_entry.st_nlink != 1:
                raise RuntimeError(f"source symlink is hard linked: {os.fsdecode(name)}")
            target = os.readlink(name, dir_fd=source_fd)
            source_after = os.stat(name, dir_fd=source_fd, follow_symlinks=False)
            if stable_identity(source_entry) != stable_identity(source_after):
                raise RuntimeError(f"source symlink changed while copying: {os.fsdecode(name)}")
            os.symlink(target, name, dir_fd=destination_fd)
            os.chown(
                name,
                source_entry.st_uid,
                source_entry.st_gid,
                dir_fd=destination_fd,
                follow_symlinks=False,
            )
        else:
            raise RuntimeError(f"unsupported source bundle entry: {os.fsdecode(name)}")
        verify_transaction_lock(f"after copying staged entry {os.fsdecode(name)}")
    if stable_identity(source_before) != stable_identity(os.fstat(source_fd)):
        raise RuntimeError("source directory changed while copying")


source_fd = -1
stage_fd = -1
try:
    if b"/" in stage_name or stage_name in (b"", b".", b".."):
        raise RuntimeError("invalid staged-bundle basename")
    verify_transaction_lock("before staged-bundle creation")
    source_before = os.lstat(source_path)
    source_fd = os.open(source_path, OPEN_DIRECTORY)
    if stable_identity(source_before) != stable_identity(os.fstat(source_fd)):
        raise RuntimeError("source bundle changed while opening")
    root_stat = os.fstat(root_fd)
    os.mkdir(stage_name, 0o700, dir_fd=root_fd)
    verify_transaction_lock("after staged-bundle directory creation")
    stage_fd = os.open(stage_name, OPEN_DIRECTORY, dir_fd=root_fd)
    copy_directory(source_fd, stage_fd)
    verify_transaction_lock("before final staged-bundle metadata updates")
    os.fchmod(stage_fd, stat.S_IMODE(source_before.st_mode))
    os.fchown(stage_fd, source_before.st_uid, source_before.st_gid)
    verify_transaction_lock("after final staged-bundle metadata updates")
    stage_stat = os.fstat(stage_fd)
    if stage_stat.st_dev != root_stat.st_dev:
        raise RuntimeError("staged bundle is not on the install-root device")
    if stable_identity(source_before) != stable_identity(os.lstat(source_path)):
        raise RuntimeError("source bundle changed during staging")
    verify_transaction_lock("after staged-bundle copy")
    visible_stage = os.stat(stage_name, dir_fd=root_fd, follow_symlinks=False)
    if identity(visible_stage) != identity(stage_stat):
        raise RuntimeError("staged bundle identity changed during copy")
    verify_transaction_lock("after staged-bundle verification")
    print(identity(stage_stat))
except (OSError, RuntimeError) as error:
    print(f"Could not create the normalized FD-anchored staged bundle: {error}", file=sys.stderr)
    sys.exit(1)
finally:
    if stage_fd >= 0:
        os.close(stage_fd)
    if source_fd >= 0:
        os.close(source_fd)
PY
  )"; then
    echo "Staging failed before target mutation; any occupied reserved path is retained for inspection." >&2
    return 1
  fi
  LAST_STAGED_IDENTITY="$staged_identity"
  assert_bound_transaction_lock "after staged-bundle preparation" || return 1
  require_physical_directory "$STAGED_APP" "Staged bundle" || return 1
  require_same_device "$INSTALL_ROOT" "$STAGED_APP" "Staged bundle" || return 1
  if [ "$(path_identity "$STAGED_APP" || true)" != "$LAST_STAGED_IDENTITY" ]; then
    echo "The visible staged bundle differs from the FD-anchored copy." >&2
    return 1
  fi
}

validate_rename_topology() {
  local target_parent
  local backup_parent
  local failed_parent

  assert_bound_transaction_lock "while validating rename topology" || return 1
  assert_bound_backup_root || return 1
  require_physical_directory "$STAGED_APP" "Staged bundle" || return 1
  require_same_device "$INSTALL_ROOT" "$BACKUP_ROOT" "Backup root" || return 1
  require_same_device "$INSTALL_ROOT" "$STAGED_APP" "Staged bundle" || return 1
  validate_reviewed_target_path || return 1

  target_parent="$(/usr/bin/dirname "$TARGET_APP")"
  backup_parent="$(/usr/bin/dirname "$BACKUP_APP")"
  failed_parent="$(/usr/bin/dirname "$FAILED_APP")"
  require_same_device "$INSTALL_ROOT" "$target_parent" "Target destination parent" || return 1
  require_same_device "$INSTALL_ROOT" "$backup_parent" "Backup destination parent" || return 1
  require_same_device "$INSTALL_ROOT" "$failed_parent" "Quarantine destination parent" || return 1

  if path_exists "$BACKUP_APP" || path_exists "$FAILED_APP"; then
    echo "A rename destination became occupied before replacement." >&2
    return 1
  fi
  if [ -z "$BOUND_INSTALL_ROOT_IDENTITY" ] \
    || [ -z "$BOUND_BACKUP_ROOT_IDENTITY" ] \
    || [ "$(path_identity "$INSTALL_ROOT" || true)" != "$BOUND_INSTALL_ROOT_IDENTITY" ] \
    || [ "$(path_identity "$BACKUP_ROOT" || true)" != "$BOUND_BACKUP_ROOT_IDENTITY" ]; then
    echo "The bound rename-parent identities changed before replacement." >&2
    return 1
  fi
  assert_bound_transaction_lock "after validating rename topology" || return 1
}

validate_test_hook_configuration() {
  local fixture_root
  local fixture_parent
  local fixture_name

  if [ -z "$TEST_HOOK_POINT" ] && [ -z "$TEST_HOOK_DIR" ]; then
    return 0
  fi
  if [ "$MODE" != "--apply" ] \
    || [ -z "$TEST_HOOK_POINT" ] \
    || [ -z "$TEST_HOOK_DIR" ]; then
    echo "Installer test hooks require an apply operation and both hook variables." >&2
    return 1
  fi
  case "$TEST_HOOK_POINT" in
    after-install-lock | inside-target-manifest-between-snapshots | before-original-backup-rename | before-replacement-rename | inside-rename-after-kernel | after-replacement-rename | before-original-restore-rename)
      ;;
    *)
      echo "Unsupported installer test hook point: $TEST_HOOK_POINT" >&2
      return 1
      ;;
  esac

  fixture_root="$(/usr/bin/dirname "$INSTALL_ROOT")"
  fixture_parent="$(/usr/bin/dirname "$fixture_root")"
  fixture_name="$(/usr/bin/basename "$fixture_root")"
  if [ "$fixture_parent" != "/private/tmp" ] \
    || [[ ! "$fixture_name" == micai-install-*.?????? ]] \
    || [ "$INSTALL_ROOT" != "$fixture_root/Applications" ] \
    || [ "$TEST_HOOK_DIR" != "$fixture_root/hooks" ]; then
    echo "Installer test hooks are restricted to an isolated /private/tmp/micai-install-* fixture." >&2
    return 1
  fi
  require_physical_directory "$fixture_root" "Installer test fixture root" || return 1
  require_physical_directory "$INSTALL_ROOT" "Installer test install root" || return 1
  require_physical_directory "$TEST_HOOK_DIR" "Installer test hook directory" || return 1
  TEST_HOOK_ENABLED=true
}

run_install_test_hook() {
  local point="$1"
  local ready_path
  local release_path

  if [ "$TEST_HOOK_ENABLED" != true ] || [ "$TEST_HOOK_POINT" != "$point" ]; then
    return 0
  fi

  ready_path="$TEST_HOOK_DIR/$point.ready"
  release_path="$TEST_HOOK_DIR/$point.release"
  if path_exists "$ready_path" || path_exists "$release_path"; then
    echo "Installer test hook marker is already occupied or a symbolic link." >&2
    return 1
  fi
  if ! /bin/mkdir "$ready_path"; then
    echo "Could not publish installer test hook readiness: $ready_path" >&2
    return 1
  fi
  require_physical_directory "$ready_path" "Installer test ready marker" || return 1

  while ! path_exists "$release_path"; do
    /bin/sleep 0.01
  done
  require_physical_directory "$release_path" "Installer test release marker" || return 1
}

LOCK_HELD=false
ORIGINAL_MOVED=false
REPLACEMENT_AT_TARGET=false
ROLLBACK_ATTEMPTED=false
ROLLBACK_COMPLETE=false
INSTALL_COMPLETE=false
INSTALL_STATE_AMBIGUOUS=false

arm_apply_signal_traps() {
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

ignore_apply_signals() {
  trap '' HUP INT TERM
}

release_apply_lock() {
  if [ "$LOCK_HELD" != true ]; then
    return 0
  fi
  if ! "$PYTHON_BIN" - \
    "$INSTALL_ROOT" \
    "$BOUND_INSTALL_ROOT_IDENTITY" \
    "$(/usr/bin/basename "$LOCK_DIR")" \
    "$BOUND_LOCK_IDENTITY" \
    "$TRANSACTION_FDS_OPEN" \
    "$TRANSACTION_ROOT_FD" \
    "$TRANSACTION_LOCK_FD" <<'PY'
import os
import stat
import sys

root_path = os.fsencode(sys.argv[1])
expected_root_identity = sys.argv[2]
lock_name = os.fsencode(sys.argv[3])
expected_lock_identity = sys.argv[4]
descriptors_open = sys.argv[5] == "true"
inherited_root_fd = int(sys.argv[6])
inherited_lock_fd = int(sys.argv[7])
OPEN_DIRECTORY = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW


def identity(value):
    return f"{value.st_dev}:{value.st_ino}"


root_fd = -1
lock_fd = -1
owns_descriptors = not descriptors_open
try:
    if descriptors_open:
        root_fd = inherited_root_fd
        lock_fd = inherited_lock_fd
    else:
        root_fd = os.open(root_path, OPEN_DIRECTORY)
        lock_fd = os.open(lock_name, OPEN_DIRECTORY, dir_fd=root_fd)
    root_stat = os.fstat(root_fd)
    visible_root = os.lstat(root_path)
    if not stat.S_ISDIR(root_stat.st_mode) \
        or not stat.S_ISDIR(visible_root.st_mode) \
        or identity(root_stat) != expected_root_identity \
        or identity(visible_root) != expected_root_identity:
        raise RuntimeError("install root differs from the lock's bound parent")
    lock_stat = os.fstat(lock_fd)
    visible_lock = os.stat(lock_name, dir_fd=root_fd, follow_symlinks=False)
    if not stat.S_ISDIR(lock_stat.st_mode) \
        or not stat.S_ISDIR(visible_lock.st_mode) \
        or identity(lock_stat) != expected_lock_identity \
        or identity(visible_lock) != expected_lock_identity:
        raise RuntimeError("visible install lock differs from the acquired lock")
    if os.listdir(lock_fd):
        raise RuntimeError("install lock is not empty")
    os.rmdir(lock_name, dir_fd=root_fd)
    try:
        os.stat(lock_name, dir_fd=root_fd, follow_symlinks=False)
    except FileNotFoundError:
        pass
    else:
        raise RuntimeError("install lock remained after removal")
    if identity(os.fstat(lock_fd)) != expected_lock_identity:
        raise RuntimeError("held install lock identity changed while releasing it")
    visible_root = os.lstat(root_path)
    if identity(os.fstat(root_fd)) != expected_root_identity \
        or not stat.S_ISDIR(visible_root.st_mode) \
        or identity(visible_root) != expected_root_identity:
        raise RuntimeError("install root changed while releasing the lock")
except (OSError, RuntimeError) as error:
    print(f"Could not release the FD-anchored install lock: {error}", file=sys.stderr)
    sys.exit(1)
finally:
    if owns_descriptors and lock_fd >= 0:
        os.close(lock_fd)
    if owns_descriptors and root_fd >= 0:
        os.close(root_fd)
PY
  then
    close_transaction_fds
    echo "Could not release the MicAI install lock: $LOCK_DIR" >&2
    echo "Inspect it manually; the installer will not delete an ambiguous lock." >&2
    return 1
  fi
  close_transaction_fds
  LOCK_HELD=false
}

record_ambiguous_rename() {
  local label="$1"

  if [ "$LAST_RENAME_OUTCOME" = "ambiguous" ]; then
    INSTALL_STATE_AMBIGUOUS=true
    echo "$label has an ambiguous kernel-rename outcome." >&2
    echo "Automatic rollback and lock removal are disabled to preserve evidence." >&2
  fi
}

rollback_install() {
  local reason="$1"
  local quarantine_state
  local quarantine_manifest
  local quarantine_signature
  ROLLBACK_ATTEMPTED=true
  echo "$reason" >&2
  echo "Attempting verified rollback." >&2

  assert_bound_transaction_lock "before rollback" || return 1
  assert_bound_backup_root || return 1
  require_same_device "$INSTALL_ROOT" "$BACKUP_ROOT" "Rollback backup root" || return 1

  if [ "$REPLACEMENT_AT_TARGET" = true ]; then
    if ! path_exists "$TARGET_APP"; then
      echo "Rollback note: the failed replacement is already absent; continuing restore." >&2
      REPLACEMENT_AT_TARGET=false
    else
      validate_bundle_path_semantics "$TARGET_APP" "Failed replacement" || return 1
      require_same_device "$INSTALL_ROOT" "$TARGET_APP" "Failed replacement" || return 1
      if path_exists "$FAILED_APP"; then
        echo "Rollback stopped: quarantine path is occupied or a symbolic link: $FAILED_APP" >&2
        return 1
      fi
      quarantine_state="$(capture_bundle_state_for_rename "$TARGET_APP" preserve)" \
        || return 1
      quarantine_manifest="${quarantine_state%%|*}"
      quarantine_signature="${quarantine_state#*|}"
      if exclusive_rename_bundle \
        "$TARGET_APP" \
        "$FAILED_APP" \
        "Failed-replacement quarantine" \
        "$quarantine_manifest" \
        "$quarantine_signature" \
        preserve; then
        REPLACEMENT_AT_TARGET=false
      else
        record_ambiguous_rename "Failed-replacement quarantine"
        echo "Rollback stopped: failed to quarantine the replacement without overwriting." >&2
        return 1
      fi
    fi
  fi

  if [ "$ORIGINAL_MOVED" = true ]; then
    if path_exists "$TARGET_APP"; then
      echo "Rollback stopped: refusing to restore over existing target: $TARGET_APP" >&2
      return 1
    fi
    if ! path_exists "$BACKUP_APP"; then
      echo "Rollback stopped: reviewed original backup is missing: $BACKUP_APP" >&2
      return 1
    fi
    if ! reviewed_target_state_matches_at "$BACKUP_APP"; then
      echo "Rollback stopped: backup does not match the reviewed original target state." >&2
      return 1
    fi
    require_same_device "$INSTALL_ROOT" "$BACKUP_APP" "Reviewed original backup" || return 1
    run_install_test_hook "before-original-restore-rename" || return 1
    if exclusive_rename_bundle \
      "$BACKUP_APP" \
      "$TARGET_APP" \
      "Reviewed-original restore" \
      "$MICAI_EXPECTED_TARGET_BUNDLE_MANIFEST_SHA256" \
      "$MICAI_EXPECTED_TARGET_SIGNATURE" \
      preserve; then
      ORIGINAL_MOVED=false
    else
      record_ambiguous_rename "Reviewed-original restore"
      echo "Rollback stopped: failed to restore the reviewed original without overwriting." >&2
      return 1
    fi
  elif path_exists "$TARGET_APP"; then
    echo "Rollback stopped: reviewed target was absent but a target now exists." >&2
    return 1
  fi

  if ! current_target_state_matches; then
    echo "Rollback verification failed: target does not match the reviewed original state." >&2
    return 1
  fi
  ROLLBACK_COMPLETE=true
  echo "Verified rollback restored the reviewed original target state." >&2
}

handle_apply_exit() {
  local status=$?
  trap - EXIT
  ignore_apply_signals

  if [ "$INSTALL_STATE_AMBIGUOUS" = true ]; then
    echo "The installer cannot prove whether the last exclusive rename committed." >&2
    echo "The FD-anchored lock is intentionally retained for manual inspection: $LOCK_DIR" >&2
    close_transaction_fds
    exit 1
  fi

  if [ "$status" -ne 0 ] \
    && [ "$INSTALL_COMPLETE" != true ] \
    && [ "$ROLLBACK_ATTEMPTED" != true ] \
    && { [ "$ORIGINAL_MOVED" = true ] || [ "$REPLACEMENT_AT_TARGET" = true ]; }
  then
    if ! rollback_install "Install exited after changing the target."; then
      echo "Automatic rollback is incomplete; inspect the printed paths manually." >&2
      INSTALL_STATE_AMBIGUOUS=true
      status=1
    fi
  fi

  if [ "$INSTALL_STATE_AMBIGUOUS" = true ]; then
    close_transaction_fds
    echo "The FD-anchored lock is intentionally retained for manual inspection: $LOCK_DIR" >&2
    exit 1
  fi

  if ! release_apply_lock; then
    status=1
  fi
  exit "$status"
}

validate_reviewed_apply_state() {
  local checkpoint="$1"
  if [ "$LOCK_HELD" = true ] && ! assert_bound_transaction_lock "$checkpoint"; then
    echo "The install root or authoritative lock changed $checkpoint. The operation is stopping." >&2
    return 1
  fi
  if ! validate_installable_bundle "$SOURCE_APP" \
    || ! expected_source_state_matches "$SOURCE_APP"; then
    echo "The source bundle changed $checkpoint. Build and review a new plan." >&2
    return 1
  fi
  if ! current_target_state_matches; then
    echo "The installed target changed $checkpoint. Review a new plan." >&2
    return 1
  fi
  require_no_running_micai "$checkpoint" || return 1
}

require_no_running_micai() {
  local checkpoint="$1"
  local pgrep_status=0

  /usr/bin/pgrep -x MicAI >/dev/null 2>&1 || pgrep_status=$?
  case "$pgrep_status" in
    0)
      echo "MicAI is running $checkpoint. Quit it normally and review a fresh plan." >&2
      return 1
      ;;
    1)
      return 0
      ;;
    *)
      echo "Could not verify whether MicAI is running $checkpoint." >&2
      echo "The installer fails closed when process inspection is unavailable." >&2
      return 1
      ;;
  esac
}

if [ "$MODE" = "--internal-bundle-state" ]; then
  INTERNAL_BUNDLE_BASENAME="${MICAI_INTERNAL_BUNDLE_BASENAME:-}"
  INTERNAL_METADATA_POLICY="${MICAI_INTERNAL_METADATA_POLICY:-}"
  if [ "${MICAI_INTERNAL_STATE_HELPER:-}" != "1" ]; then
    echo "Internal bundle-state mode requires its transaction-helper marker." >&2
    exit 2
  fi
  case "$INTERNAL_BUNDLE_BASENAME" in
    "" | "." | ".." | */* | *$'\n'* | *$'\r'*)
      echo "Internal bundle-state mode requires a safe single basename." >&2
      exit 2
      ;;
  esac
  case "$INTERNAL_METADATA_POLICY" in
    preserve | normalized)
      ;;
    *)
      echo "Internal bundle-state mode requires a supported metadata policy." >&2
      exit 2
      ;;
  esac
  require_physical_directory "$INTERNAL_BUNDLE_BASENAME" \
    "FD-anchored bundle-state source" || exit 1
  INTERNAL_MANIFEST_BEFORE="$(bundle_manifest_sha256 \
    "$INTERNAL_BUNDLE_BASENAME" "$INTERNAL_METADATA_POLICY")" || exit 1
  INTERNAL_SIGNATURE="$(signature_state "$INTERNAL_BUNDLE_BASENAME")" || exit 1
  INTERNAL_MANIFEST_AFTER="$(bundle_manifest_sha256 \
    "$INTERNAL_BUNDLE_BASENAME" "$INTERNAL_METADATA_POLICY")" || exit 1
  if [ "$INTERNAL_MANIFEST_BEFORE" != "$INTERNAL_MANIFEST_AFTER" ]; then
    echo "FD-anchored bundle state changed while its signature was checked." >&2
    exit 1
  fi
  printf '%s|%s\n' "$INTERNAL_MANIFEST_AFTER" "$INTERNAL_SIGNATURE"
  exit 0
fi

if [ ! -x "$PYTHON_BIN" ]; then
  echo "Missing required macOS installer helper runtime: $PYTHON_BIN" >&2
  exit 1
fi
if ! "$PYTHON_BIN" -c \
  'import ctypes; getattr(ctypes.CDLL(None), "renameatx_np")' >/dev/null 2>&1; then
  echo "The installer helper runtime cannot access Darwin renameatx_np." >&2
  exit 1
fi
if [ "$MODE" = "--plan" ] && ! validate_test_hook_configuration; then
  exit 1
fi

if ! validate_installable_bundle "$SOURCE_APP"; then
  echo "Build a fresh source bundle with: bash '$SCRIPT_DIR/codex-build.sh'" >&2
  exit 1
fi

SOURCE_EXECUTABLE="$SOURCE_APP/Contents/MacOS/MicAI"
SOURCE_ICON="$SOURCE_APP/Contents/Resources/MicAI.icns"
SOURCE_PLIST="$SOURCE_APP/Contents/Info.plist"
SOURCE_MANIFEST_BEFORE="$(bundle_manifest_sha256 "$SOURCE_APP" normalized)"
SOURCE_EXECUTABLE_SHA256="$(sha256_file "$SOURCE_EXECUTABLE")"
SOURCE_ICON_SHA256="$(sha256_file "$SOURCE_ICON")"
SOURCE_PLIST_SHA256="$(sha256_file "$SOURCE_PLIST")"
/usr/bin/codesign --verify --deep --strict "$SOURCE_APP"
SOURCE_BUNDLE_MANIFEST_SHA256="$(bundle_manifest_sha256 "$SOURCE_APP" normalized)"
if [ "$SOURCE_MANIFEST_BEFORE" != "$SOURCE_BUNDLE_MANIFEST_SHA256" ]; then
  echo "The source bundle changed while its plan state was being captured." >&2
  exit 1
fi

if [ "$MODE" = "--plan" ]; then
  if ! validate_plan_path_semantics; then
    echo "Install plan stopped because a target or reserved path is ambiguous." >&2
    exit 1
  fi
  TARGET_EXECUTABLE="$(bundle_executable_path "$TARGET_APP")" || exit 1
  TARGET_ICON="$(bundle_icon_path "$TARGET_APP")" || exit 1
  TARGET_PLIST="$TARGET_APP/Contents/Info.plist"
  INSTALL_ROOT_PRESENT="no"
  INSTALL_ROOT_IDENTITY="<missing>"
  if path_exists "$INSTALL_ROOT"; then
    INSTALL_ROOT_PRESENT="yes"
    INSTALL_ROOT_IDENTITY="$(path_identity "$INSTALL_ROOT")"
  fi
  TARGET_PRESENT="no"
  if path_exists "$TARGET_APP"; then
    TARGET_PRESENT="yes"
  fi
  TARGET_MANIFEST_BEFORE="$(bundle_manifest_or_missing "$TARGET_APP")"
  TARGET_EXECUTABLE_SHA256="$(hash_or_missing "$TARGET_EXECUTABLE")"
  TARGET_ICON_SHA256="$(hash_or_missing "$TARGET_ICON")"
  TARGET_PLIST_SHA256="$(hash_or_missing "$TARGET_PLIST")"
  TARGET_SIGNATURE="$(signature_state "$TARGET_APP")"
  TARGET_BUNDLE_MANIFEST_SHA256="$(bundle_manifest_or_missing "$TARGET_APP")"
  if [ "$TARGET_MANIFEST_BEFORE" != "$TARGET_BUNDLE_MANIFEST_SHA256" ]; then
    echo "The current installed target changed while its plan state was being captured." >&2
    exit 1
  fi
  if [ "$INSTALL_ROOT_PRESENT" = "yes" ] \
    && [ "$(path_identity "$INSTALL_ROOT" || true)" != "$INSTALL_ROOT_IDENTITY" ]; then
    echo "The install root changed while its plan state was being captured." >&2
    exit 1
  fi

  echo "MicAI persistent install plan (read-only; no files changed)"
  echo
  echo "Source validation: PASS"
  echo "Installer helper runtime: $PYTHON_BIN (stable metadata manifest + Darwin renameatx_np)"
  bundle_report "Source bundle:" "$SOURCE_APP"
  echo
  bundle_report "Current installed target:" "$TARGET_APP"
  echo
  echo "Source vs current target equivalence:"
  echo "  Executable source: $SOURCE_EXECUTABLE_SHA256"
  echo "  Executable target: $TARGET_EXECUTABLE_SHA256"
  if [ "$SOURCE_EXECUTABLE_SHA256" = "$TARGET_EXECUTABLE_SHA256" ]; then
    echo "  Executable result: MATCH"
  else
    echo "  Executable result: MISMATCH"
  fi
  echo "  Icon source: $SOURCE_ICON_SHA256"
  echo "  Icon target: $TARGET_ICON_SHA256"
  if [ "$SOURCE_ICON_SHA256" = "$TARGET_ICON_SHA256" ]; then
    echo "  Icon result: MATCH"
  else
    echo "  Icon result: MISMATCH"
  fi
  echo "  Info.plist source: $SOURCE_PLIST_SHA256"
  echo "  Info.plist target: $TARGET_PLIST_SHA256"
  if [ "$SOURCE_PLIST_SHA256" = "$TARGET_PLIST_SHA256" ]; then
    echo "  Info.plist result: MATCH"
  else
    echo "  Info.plist result: MISMATCH"
  fi
  echo "  Full bundle-state manifest source: $SOURCE_BUNDLE_MANIFEST_SHA256"
  echo "  Full bundle-state manifest target: $TARGET_BUNDLE_MANIFEST_SHA256"
  if [ "$SOURCE_BUNDLE_MANIFEST_SHA256" = "$TARGET_BUNDLE_MANIFEST_SHA256" ]; then
    echo "  Full bundle-state manifest result: MATCH"
  else
    echo "  Full bundle-state manifest result: MISMATCH"
  fi
  echo
  echo "Planned persistent paths:"
  echo "  Source: $SOURCE_APP"
  echo "  Target: $TARGET_APP"
  echo "  Staged copy: $STAGED_APP"
  echo "  Recoverable backup: $BACKUP_APP"
  echo "  Failed replacement quarantine: $FAILED_APP"
  echo "  Atomic apply lock: $LOCK_DIR"
  echo "  Install-root presence: $INSTALL_ROOT_PRESENT"
  echo "  Install-root device/inode: $INSTALL_ROOT_IDENTITY"
  echo "  Staging metadata policy: normalized (no ACLs, xattrs, flags, or file hardlinks)"
  echo
  echo "Rollback behavior:"
  echo "  If final verification fails, the replacement moves to the quarantine path"
  echo "  and the prior target is restored from the backup automatically. After a"
  echo "  successful install, the backup remains available for a separately approved rollback."
  echo "  Rollback verifies the exact reviewed target state; an existing lock or"
  echo "  ambiguous rollback destination is never deleted or overwritten automatically."
  echo
  if ! captured_plan_state_matches; then
    echo "Plan capture changed before issuance; no apply command was emitted." >&2
    exit 1
  fi
  echo "Exact apply operation (DO NOT RUN without explicit approval for $TARGET_APP):"
  printf '  '
  print_shell_assignment MICAI_INSTALL_DIR "$INSTALL_ROOT"
  printf ' '
  print_shell_assignment MICAI_INSTALL_APPROVED_TARGET "$TARGET_APP"
  printf ' '
  print_shell_assignment MICAI_INSTALL_ID "$INSTALL_ID"
  printf ' '
  print_shell_assignment MICAI_EXPECTED_INSTALL_ROOT_PRESENT "$INSTALL_ROOT_PRESENT"
  printf ' '
  print_shell_assignment MICAI_EXPECTED_INSTALL_ROOT_IDENTITY "$INSTALL_ROOT_IDENTITY"
  printf ' '
  print_shell_assignment MICAI_EXPECTED_EXECUTABLE_SHA256 "$SOURCE_EXECUTABLE_SHA256"
  printf ' '
  print_shell_assignment MICAI_EXPECTED_ICON_SHA256 "$SOURCE_ICON_SHA256"
  printf ' '
  print_shell_assignment MICAI_EXPECTED_PLIST_SHA256 "$SOURCE_PLIST_SHA256"
  printf ' '
  print_shell_assignment MICAI_EXPECTED_BUNDLE_MANIFEST_SHA256 \
    "$SOURCE_BUNDLE_MANIFEST_SHA256"
  printf ' '
  print_shell_assignment MICAI_EXPECTED_TARGET_PRESENT "$TARGET_PRESENT"
  printf ' '
  print_shell_assignment MICAI_EXPECTED_TARGET_EXECUTABLE_SHA256 \
    "$TARGET_EXECUTABLE_SHA256"
  printf ' '
  print_shell_assignment MICAI_EXPECTED_TARGET_ICON_SHA256 "$TARGET_ICON_SHA256"
  printf ' '
  print_shell_assignment MICAI_EXPECTED_TARGET_PLIST_SHA256 "$TARGET_PLIST_SHA256"
  printf ' '
  print_shell_assignment MICAI_EXPECTED_TARGET_BUNDLE_MANIFEST_SHA256 \
    "$TARGET_BUNDLE_MANIFEST_SHA256"
  printf ' '
  print_shell_assignment MICAI_EXPECTED_TARGET_SIGNATURE "$TARGET_SIGNATURE"
  printf ' '
  print_shell_word /bin/bash
  printf ' '
  print_shell_word "$SCRIPT_DIR/codex-install.sh"
  printf ' '
  print_shell_word --apply
  printf '\n'
  echo
  echo "The apply path does not rebuild, launch MicAI, or mutate LaunchServices."
  exit 0
fi

if [ "${MICAI_INSTALL_APPROVED_TARGET:-}" != "$TARGET_APP" ]; then
  echo "--apply requires MICAI_INSTALL_APPROVED_TARGET to equal: $TARGET_APP" >&2
  exit 1
fi
if [ -z "${MICAI_INSTALL_ID:-}" ]; then
  echo "--apply requires the MICAI_INSTALL_ID printed by --plan." >&2
  exit 1
fi
if [ -z "${MICAI_EXPECTED_EXECUTABLE_SHA256:-}" ] \
  || [ -z "${MICAI_EXPECTED_ICON_SHA256:-}" ] \
  || [ -z "${MICAI_EXPECTED_PLIST_SHA256:-}" ] \
  || [ -z "${MICAI_EXPECTED_BUNDLE_MANIFEST_SHA256:-}" ]; then
  echo "--apply requires all source hashes printed by --plan." >&2
  exit 1
fi
if [ -z "${MICAI_EXPECTED_INSTALL_ROOT_PRESENT:-}" ] \
  || [ -z "${MICAI_EXPECTED_INSTALL_ROOT_IDENTITY:-}" ]; then
  echo "--apply requires the install-root state printed by --plan." >&2
  exit 1
fi
if [ -z "${MICAI_EXPECTED_TARGET_PRESENT:-}" ] \
  || [ -z "${MICAI_EXPECTED_TARGET_EXECUTABLE_SHA256:-}" ] \
  || [ -z "${MICAI_EXPECTED_TARGET_ICON_SHA256:-}" ] \
  || [ -z "${MICAI_EXPECTED_TARGET_PLIST_SHA256:-}" ] \
  || [ -z "${MICAI_EXPECTED_TARGET_BUNDLE_MANIFEST_SHA256:-}" ] \
  || [ -z "${MICAI_EXPECTED_TARGET_SIGNATURE:-}" ]; then
  echo "--apply requires the complete current-target state printed by --plan." >&2
  exit 1
fi
if ! validate_test_hook_configuration; then
  exit 1
fi
if ! require_no_running_micai "during the apply preflight"; then
  echo "BLOCKED/SKIPPED: MicAI process state prevents the persistent install." >&2
  exit 77
fi
if ! prepare_install_root_for_apply; then
  exit 1
fi
if ! acquire_apply_lock; then
  exit 1
fi
trap handle_apply_exit EXIT
arm_apply_signal_traps

if ! run_install_test_hook "after-install-lock" \
  || ! assert_bound_transaction_lock "after the install-lock hook"; then
  exit 1
fi

if ! validate_reviewed_apply_state "after acquiring the install lock"; then
  exit 1
fi
if ! validate_backup_root_if_present \
  || ! validate_reserved_paths_absent \
  || ! prepare_backup_root_for_apply \
  || ! prepare_staged_bundle; then
  exit 1
fi
if ! validate_installable_bundle "$STAGED_APP" \
  || ! expected_source_state_matches "$STAGED_APP"; then
  echo "Staged verification failed. The installed target was not changed." >&2
  echo "Inspect or remove the staged copy manually: $STAGED_APP" >&2
  exit 1
fi
if ! validate_reviewed_apply_state "immediately before replacement"; then
  echo "Inspect or remove the staged copy manually: $STAGED_APP" >&2
  exit 1
fi
if ! validate_rename_topology; then
  echo "Rename topology changed before replacement; the target was not changed." >&2
  echo "Inspect or remove the staged copy manually: $STAGED_APP" >&2
  exit 1
fi

# Keep the two same-volume renames and their state markers indivisible from the
# shell's signal traps. A process crash can still leave the lock for inspection,
# but an ordinary signal cannot land between a successful move and its marker.
ignore_apply_signals
if path_exists "$TARGET_APP"; then
  if ! run_install_test_hook "before-original-backup-rename"; then
    exit 1
  fi
  if exclusive_rename_bundle \
    "$TARGET_APP" \
    "$BACKUP_APP" \
    "Reviewed-original backup" \
    "$MICAI_EXPECTED_TARGET_BUNDLE_MANIFEST_SHA256" \
    "$MICAI_EXPECTED_TARGET_SIGNATURE" \
    preserve; then
    ORIGINAL_MOVED=true
  else
    record_ambiguous_rename "Reviewed-original backup"
    echo "Could not move the reviewed original bundle to its backup path without overwriting." >&2
    exit 1
  fi
  if ! reviewed_target_state_matches_at "$BACKUP_APP"; then
    echo "The backup does not match the reviewed original target state." >&2
    exit 1
  fi
fi

if ! run_install_test_hook "before-replacement-rename"; then
  if rollback_install "Replacement test synchronization failed."; then
    echo "Replacement did not begin; the reviewed original target state was restored." >&2
  else
    INSTALL_STATE_AMBIGUOUS=true
  fi
  exit 1
fi
if exclusive_rename_bundle \
  "$STAGED_APP" \
  "$TARGET_APP" \
  "Staged replacement" \
  "$MICAI_EXPECTED_BUNDLE_MANIFEST_SHA256" \
  valid \
  normalized; then
  REPLACEMENT_AT_TARGET=true
else
  record_ambiguous_rename "Staged replacement"
  if [ "$INSTALL_STATE_AMBIGUOUS" = true ]; then
    echo "Replacement move outcome is ambiguous; automatic rollback is disabled." >&2
  else
    if rollback_install "Replacement move failed."; then
      echo "Replacement failed; the reviewed original target state was restored." >&2
    else
      INSTALL_STATE_AMBIGUOUS=true
      echo "Replacement failed and rollback is incomplete; inspect paths manually." >&2
    fi
  fi
  exit 1
fi
if [ "$TEST_HOOK_ENABLED" = true ] \
  && [ "$TEST_HOOK_POINT" = "before-original-restore-rename" ]; then
  if rollback_install "Temp-fixture fault injection requested a verified rollback."; then
    echo "Temp-fixture rollback completed without installing the replacement." >&2
  else
    INSTALL_STATE_AMBIGUOUS=true
    echo "Temp-fixture rollback is incomplete; the lock and evidence are retained." >&2
  fi
  exit 1
fi
arm_apply_signal_traps
if ! run_install_test_hook "after-replacement-rename"; then
  ignore_apply_signals
  if rollback_install "Replacement test synchronization failed."; then
    echo "The reviewed original target state was restored." >&2
  else
    INSTALL_STATE_AMBIGUOUS=true
  fi
  exit 1
fi

if ! validate_installable_bundle "$TARGET_APP" \
  || ! expected_source_state_matches "$TARGET_APP"; then
  ignore_apply_signals
  if rollback_install "Final replacement verification failed."; then
    echo "The reviewed original target state was restored." >&2
    if path_exists "$FAILED_APP"; then
      echo "Failed replacement retained at: $FAILED_APP" >&2
    fi
  else
    INSTALL_STATE_AMBIGUOUS=true
    echo "Final verification failed and rollback is incomplete; inspect paths manually." >&2
  fi
  exit 1
fi

INSTALL_COMPLETE=true
echo "Installed and verified: $TARGET_APP"
if [ "$ORIGINAL_MOVED" = true ]; then
  echo "Recoverable prior bundle: $BACKUP_APP"
fi
echo "LaunchServices was not explicitly mutated."
