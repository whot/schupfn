#!/usr/bin/env bats

load test_helper

setup() {
    reset_die
    TMPDIR="$(make_tmpdir)"
    # Override SESSION_DIR to use a temp directory
    SESSION_DIR="$TMPDIR/sessions"
}

teardown() {
    rm -rf "$TMPDIR"
}

# ── write_session / read_session ────────────────────────────────────────────

@test "write_session: creates session file with correct contents" {
    write_session "mybox" "12345" "54321" "/home/user/project" ""

    local session_file="$SESSION_DIR/mybox-12345.session"
    [ -f "$session_file" ]

    run read_session "$session_file" "name"
    [ "$output" = "mybox" ]

    run read_session "$session_file" "pid"
    [ "$output" = "12345" ]

    run read_session "$session_file" "ssh_port"
    [ "$output" = "54321" ]

    run read_session "$session_file" "workdir"
    [ "$output" = "/home/user/project" ]
}

@test "write_session: stores ssh_key when provided" {
    write_session "mybox" "12345" "54321" "/tmp" "/home/user/.ssh/id_ed25519"

    local session_file="$SESSION_DIR/mybox-12345.session"
    run read_session "$session_file" "ssh_key"
    [ "$output" = "/home/user/.ssh/id_ed25519" ]
}

@test "write_session: ssh_key is empty when not provided" {
    write_session "mybox" "12345" "54321" "/tmp" ""

    local session_file="$SESSION_DIR/mybox-12345.session"
    run read_session "$session_file" "ssh_key"
    [ "$output" = "" ]
}

@test "write_session: stores started_at timestamp" {
    write_session "mybox" "12345" "54321" "/tmp" ""

    local session_file="$SESSION_DIR/mybox-12345.session"
    run read_session "$session_file" "started_at"
    [ -n "$output" ]
}

@test "write_session: creates SESSION_DIR if it does not exist" {
    [ ! -d "$SESSION_DIR" ]

    write_session "mybox" "12345" "54321" "/tmp" ""

    [ -d "$SESSION_DIR" ]
}

@test "write_session: multiple VMs for same container get separate files" {
    write_session "mybox" "100" "50001" "/tmp" ""
    write_session "mybox" "200" "50002" "/tmp" ""

    [ -f "$SESSION_DIR/mybox-100.session" ]
    [ -f "$SESSION_DIR/mybox-200.session" ]

    run read_session "$SESSION_DIR/mybox-100.session" "ssh_port"
    [ "$output" = "50001" ]

    run read_session "$SESSION_DIR/mybox-200.session" "ssh_port"
    [ "$output" = "50002" ]
}

# ── read_session ────────────────────────────────────────────────────────────

@test "read_session: returns empty for missing key" {
    write_session "mybox" "12345" "54321" "/tmp" ""

    local session_file="$SESSION_DIR/mybox-12345.session"
    run read_session "$session_file" "nonexistent"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# ── remove_session ──────────────────────────────────────────────────────────

@test "remove_session: removes the session file" {
    write_session "mybox" "12345" "54321" "/tmp" ""
    [ -f "$SESSION_DIR/mybox-12345.session" ]

    remove_session "mybox" "12345"
    [ ! -f "$SESSION_DIR/mybox-12345.session" ]
}

@test "remove_session: does not fail if file does not exist" {
    run remove_session "mybox" "99999"
    [ "$status" -eq 0 ]
}

# ── cleanup_stale_sessions ──────────────────────────────────────────────────

@test "cleanup_stale_sessions: removes sessions with dead PIDs" {
    # Use a PID that almost certainly does not exist
    write_session "mybox" "9999999" "54321" "/tmp" ""
    [ -f "$SESSION_DIR/mybox-9999999.session" ]

    cleanup_stale_sessions
    [ ! -f "$SESSION_DIR/mybox-9999999.session" ]
}

@test "cleanup_stale_sessions: removes sessions with missing pid" {
    mkdir -p "$SESSION_DIR"
    cat > "$SESSION_DIR/corrupt-0.session" <<EOF
name=corrupt
ssh_port=54321
workdir=/tmp
ssh_key=
started_at=2025-01-01T00:00:00+00:00
EOF
    [ -f "$SESSION_DIR/corrupt-0.session" ]

    cleanup_stale_sessions
    [ ! -f "$SESSION_DIR/corrupt-0.session" ]
}

@test "cleanup_stale_sessions: removes sessions with empty pid" {
    mkdir -p "$SESSION_DIR"
    cat > "$SESSION_DIR/corrupt-0.session" <<EOF
name=corrupt
pid=
ssh_port=54321
workdir=/tmp
ssh_key=
started_at=2025-01-01T00:00:00+00:00
EOF
    [ -f "$SESSION_DIR/corrupt-0.session" ]

    cleanup_stale_sessions
    [ ! -f "$SESSION_DIR/corrupt-0.session" ]
}

@test "cleanup_stale_sessions: removes sessions with non-numeric pid" {
    mkdir -p "$SESSION_DIR"
    cat > "$SESSION_DIR/corrupt-0.session" <<EOF
name=corrupt
pid=notanumber
ssh_port=54321
workdir=/tmp
ssh_key=
started_at=2025-01-01T00:00:00+00:00
EOF
    [ -f "$SESSION_DIR/corrupt-0.session" ]

    cleanup_stale_sessions
    [ ! -f "$SESSION_DIR/corrupt-0.session" ]
}

@test "cleanup_stale_sessions: keeps sessions with live PIDs" {
    # Use our own PID — guaranteed to be alive
    local my_pid=$$
    write_session "mybox" "$my_pid" "54321" "/tmp" ""
    [ -f "$SESSION_DIR/mybox-${my_pid}.session" ]

    cleanup_stale_sessions
    [ -f "$SESSION_DIR/mybox-${my_pid}.session" ]
}

@test "cleanup_stale_sessions: succeeds when SESSION_DIR does not exist" {
    rm -rf "$SESSION_DIR"
    run cleanup_stale_sessions
    [ "$status" -eq 0 ]
}

# ── list_active_sessions ───────────────────────────────────────────────────

@test "list_active_sessions: returns sessions for live PIDs" {
    local my_pid=$$
    write_session "mybox" "$my_pid" "54321" "/tmp" ""

    run list_active_sessions
    [ "$status" -eq 0 ]
    [[ "$output" == *"mybox-${my_pid}.session"* ]]
}

@test "list_active_sessions: filters by container name" {
    local my_pid=$$
    write_session "mybox" "$my_pid" "54321" "/tmp" ""
    # Use a dead PID for the other container so it's cleaned up, or
    # use a second "live" session with a different name trick.
    # Actually, just write two sessions with our PID but different names
    # (the filename differs so they're separate files).
    write_session "otherbox" "$my_pid" "54322" "/tmp" ""

    run list_active_sessions "mybox"
    [ "$status" -eq 0 ]
    [[ "$output" == *"mybox-${my_pid}.session"* ]]
    [[ "$output" != *"otherbox"* ]]
}

@test "list_active_sessions: returns nothing when no sessions exist" {
    run list_active_sessions
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "list_active_sessions: returns nothing for unknown container name" {
    local my_pid=$$
    write_session "mybox" "$my_pid" "54321" "/tmp" ""

    run list_active_sessions "unknown"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "list_active_sessions: excludes stale sessions" {
    # Dead PID
    write_session "deadbox" "9999999" "54321" "/tmp" ""
    # Live PID
    local my_pid=$$
    write_session "livebox" "$my_pid" "54322" "/tmp" ""

    run list_active_sessions
    [ "$status" -eq 0 ]
    [[ "$output" == *"livebox"* ]]
    [[ "$output" != *"deadbox"* ]]
}

# ── acquire_join_lock / release_join_lock ───────────────────────────────────

@test "acquire_join_lock: creates lock file" {
    acquire_join_lock "mybox" "1000" "2000"

    [ -f "$SESSION_DIR/mybox-1000.join.2000" ]
}

@test "acquire_join_lock: creates SESSION_DIR if it does not exist" {
    [ ! -d "$SESSION_DIR" ]

    acquire_join_lock "mybox" "1000" "2000"

    [ -d "$SESSION_DIR" ]
}

@test "acquire_join_lock: multiple joins create separate files" {
    acquire_join_lock "mybox" "1000" "2000"
    acquire_join_lock "mybox" "1000" "3000"

    [ -f "$SESSION_DIR/mybox-1000.join.2000" ]
    [ -f "$SESSION_DIR/mybox-1000.join.3000" ]
}

@test "acquire_join_lock: no-op when SESSION_DIR is empty" {
    SESSION_DIR=""
    run acquire_join_lock "mybox" "1000" "2000"
    [ "$status" -eq 0 ]
}

@test "release_join_lock: removes lock file" {
    acquire_join_lock "mybox" "1000" "2000"
    [ -f "$SESSION_DIR/mybox-1000.join.2000" ]

    release_join_lock "mybox" "1000" "2000"
    [ ! -f "$SESSION_DIR/mybox-1000.join.2000" ]
}

@test "release_join_lock: does not fail if file does not exist" {
    run release_join_lock "mybox" "1000" "9999"
    [ "$status" -eq 0 ]
}

@test "release_join_lock: does not remove other locks" {
    acquire_join_lock "mybox" "1000" "2000"
    acquire_join_lock "mybox" "1000" "3000"

    release_join_lock "mybox" "1000" "2000"

    [ ! -f "$SESSION_DIR/mybox-1000.join.2000" ]
    [ -f "$SESSION_DIR/mybox-1000.join.3000" ]
}

@test "release_join_lock: no-op when SESSION_DIR is empty" {
    SESSION_DIR=""
    run release_join_lock "mybox" "1000" "2000"
    [ "$status" -eq 0 ]
}

# ── count_active_joins ─────────────────────────────────────────────────────

@test "count_active_joins: returns 0 when no joins exist" {
    run count_active_joins "mybox" "1000"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "count_active_joins: returns 0 when SESSION_DIR does not exist" {
    rm -rf "$SESSION_DIR"
    run count_active_joins "mybox" "1000"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "count_active_joins: counts live join sessions" {
    # Use our own PID — guaranteed to be alive
    local my_pid=$$
    acquire_join_lock "mybox" "1000" "$my_pid"

    run count_active_joins "mybox" "1000"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "count_active_joins: removes stale join locks" {
    # Use a dead PID
    acquire_join_lock "mybox" "1000" "9999999"
    [ -f "$SESSION_DIR/mybox-1000.join.9999999" ]

    run count_active_joins "mybox" "1000"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]

    # Lock file should have been cleaned up
    [ ! -f "$SESSION_DIR/mybox-1000.join.9999999" ]
}

@test "count_active_joins: counts only live joins, removes stale" {
    local my_pid=$$
    acquire_join_lock "mybox" "1000" "$my_pid"
    acquire_join_lock "mybox" "1000" "9999999"

    run count_active_joins "mybox" "1000"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]

    # Stale lock removed, live lock remains
    [ ! -f "$SESSION_DIR/mybox-1000.join.9999999" ]
    [ -f "$SESSION_DIR/mybox-1000.join.${my_pid}" ]
}

@test "count_active_joins: does not count joins for other VMs" {
    local my_pid=$$
    acquire_join_lock "mybox" "1000" "$my_pid"
    acquire_join_lock "mybox" "2000" "$my_pid"

    run count_active_joins "mybox" "1000"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "count_active_joins: removes lock with non-numeric join PID" {
    mkdir -p "$SESSION_DIR"
    touch "$SESSION_DIR/mybox-1000.join.notapid"

    run count_active_joins "mybox" "1000"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
    [ ! -f "$SESSION_DIR/mybox-1000.join.notapid" ]
}
