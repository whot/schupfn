#!/bin/bash
#
# opencode-wrapper — wrapper for running opencode inside a schupfn VM
#
# This script wraps the real opencode binary. On exit, it copies the
# VM-local opencode database to a staging directory on an export-rw
# mount so the host can import new sessions after the VM shuts down.
#
# The staging directory is $SCHUPFN_SYNC_DIR (default:
#   $SCHUPFN_WORKDIR/.schupfn/opencode-sync/$SCHUPFN_UUID
# or if SCHUPFN_WORKDIR is unset:
#   $PWD/.schupfn/opencode-sync/$SCHUPFN_UUID)
#
# SCHUPFN_UUID is set automatically by the VM boot process via
# /etc/profile.d/schupfn-uuid.sh. It uniquely identifies this VM
# session so multiple concurrent VMs don't clobber each other's
# staging files.
#
# Files written to the staging directory:
#   opencode.db  - copy of the VM's opencode database
#   timestamp    - milliseconds-since-epoch recorded before the first
#                  opencode invocation (written once, not overwritten)
#
# Requires: the real opencode binary at $SCHUPFN_OPENCODE
#           (default: ~/.opencode/bin/opencode)

set -uo pipefail

REAL_OPENCODE="${SCHUPFN_OPENCODE:-$HOME/.opencode/bin/opencode}"
WORKDIR="${SCHUPFN_WORKDIR:-$PWD}"
UUID="${SCHUPFN_UUID:-}"

if [ -z "$UUID" ]; then
    echo "opencode-wrapper: SCHUPFN_UUID not set (not running in a schupfn VM?)" >&2
    exec "$REAL_OPENCODE" "$@"
fi

SYNC_DIR="${SCHUPFN_SYNC_DIR:-$WORKDIR/.schupfn/opencode-sync/$UUID}"

if [ ! -x "$REAL_OPENCODE" ]; then
    echo "opencode-wrapper: real opencode not found at $REAL_OPENCODE" >&2
    exit 127
fi

# Record timestamp before the first invocation only.
# This ensures all sessions created across multiple opencode runs
# within a single VM session are captured.
mkdir -p "$SYNC_DIR"
if [ ! -f "$SYNC_DIR/timestamp" ]; then
    date +%s%3N > "$SYNC_DIR/timestamp"
fi

# Run the real opencode, passing through all arguments.
"$REAL_OPENCODE" "$@"
rc=$?

# Copy the database to the staging directory.
# opencode stores its db at $XDG_DATA_HOME/opencode/opencode.db
# (default: ~/.local/share/opencode/opencode.db).
db_path=$("$REAL_OPENCODE" db path 2>/dev/null)
if [ -z "$db_path" ]; then
    db_path="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/opencode.db"
fi

if [ -f "$db_path" ]; then
    # Checkpoint WAL to ensure all data is in the main db file,
    # then copy. This avoids needing to copy -wal and -shm files.
    sqlite3 "$db_path" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    cp "$db_path" "$SYNC_DIR/opencode.db" 2>/dev/null || {
        echo "opencode-wrapper: failed to copy database to staging" >&2
    }
else
    echo "opencode-wrapper: database not found at $db_path" >&2
fi

exit $rc
