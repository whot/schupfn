#!/bin/bash
#
# schupfn-opencode-sync — import opencode sessions from a staged database
#
# Usage:
#   schupfn-opencode-sync <sync-dir>
#
# The sync directory must contain:
#   opencode.db  - copy of the VM's opencode database
#   timestamp    - milliseconds-since-epoch from before first opencode run
#
# This script copies the database to a tmpdir, finds sessions created
# after the timestamp, exports each one, and imports them into the
# host's opencode database. The sync directory is removed on success.
#
# Example .schupfn/config.yml:
#   export-cow:
#     - ~/.local/share/opencode
#   on-exit: "schupfn-opencode-sync {workdir}/.schupfn/opencode-sync/{uuid}"

set -uo pipefail

PREFIX="schupfn-opencode-sync"
OPENCODE="${SCHUPFN_OPENCODE:-$HOME/.opencode/bin/opencode}"

SYNC_DIR="${1:-}"
if [ -z "$SYNC_DIR" ]; then
    echo "Usage: $0 <sync-dir>" >&2
    exit 1
fi

if [ ! -f "$SYNC_DIR/opencode.db" ]; then
    echo "$PREFIX: no staged database found (opencode may not have run)"
    exit 0
fi

if [ ! -f "$SYNC_DIR/timestamp" ]; then
    echo "$PREFIX: no timestamp found, cannot determine new sessions" >&2
    exit 0
fi

boot_ms=$(cat "$SYNC_DIR/timestamp")

# Copy the staged db to a tmpdir so we can operate on it locally
# (the staged copy is on a 9p export-rw mount)
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/schupfn-opencode-sync.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/opencode"
cp "$SYNC_DIR/opencode.db" "$tmpdir/opencode/opencode.db" || {
    echo "$PREFIX: failed to copy staged database" >&2
    exit 0
}

# Query the copy for sessions created during this VM session
session_json=$(XDG_DATA_HOME="$tmpdir" "$OPENCODE" db --format json \
    "SELECT id FROM session WHERE time_created >= $boot_ms" 2>/dev/null) || {
    echo "$PREFIX: failed to query staged database" >&2
    exit 0
}

# Parse session IDs
ids=()
while IFS= read -r id; do
    [ -n "$id" ] && ids+=("$id")
done < <(echo "$session_json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for row in data:
        print(row['id'])
except:
    pass
" 2>/dev/null)

if [ ${#ids[@]} -eq 0 ]; then
    echo "$PREFIX: no new sessions to import"
    rm -rf "$SYNC_DIR"
    exit 0
fi

echo "$PREFIX: found ${#ids[@]} new session(s) to import"

# Export each session from the copy, import into the host's db
count=0
failed=0
for sid in "${ids[@]}"; do
    export_file="$tmpdir/${sid}.json"

    # Export from the staged db copy
    XDG_DATA_HOME="$tmpdir" "$OPENCODE" export "$sid" > "$export_file" 2>/dev/null || {
        echo "$PREFIX: failed to export session $sid" >&2
        failed=$((failed + 1))
        continue
    }

    # Sanity check: is the export valid JSON?
    if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$export_file" 2>/dev/null; then
        echo "$PREFIX: invalid export for session $sid, skipping" >&2
        failed=$((failed + 1))
        continue
    fi

    # Import into the host's real database
    "$OPENCODE" import "$export_file" 2>/dev/null || {
        echo "$PREFIX: failed to import session $sid" >&2
        failed=$((failed + 1))
        continue
    }

    count=$((count + 1))
done

echo "$PREFIX: imported $count session(s) from VM to host"
if [ "$failed" -gt 0 ]; then
    echo "$PREFIX: $failed session(s) failed to sync" >&2
fi

# Clean up staging directory
rm -rf "$SYNC_DIR"
