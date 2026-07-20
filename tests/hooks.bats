#!/usr/bin/env bats

load test_helper

setup() {
    reset_die
    TMPDIR="$(make_tmpdir)"
}

teardown() {
    rm -rf "$TMPDIR"
}

# ── run_hook ────────────────────────────────────────────────────────────────

@test "run_hook: empty command is a no-op" {
    run_hook "on-enter" "" "1234" "/path/key" "myvm" "/work"
    assert_no_warnings
}

@test "run_hook: expands {ssh_port} placeholder" {
    local outfile="$TMPDIR/out"
    run_hook "on-enter" "echo {ssh_port} > '$outfile'" "5555" "/path/key" "myvm" "/work"
    [ "$(cat "$outfile")" = "5555" ]
}

@test "run_hook: expands {ssh_key} placeholder" {
    local outfile="$TMPDIR/out"
    run_hook "on-enter" "echo {ssh_key} > '$outfile'" "1234" "/my/key" "myvm" "/work"
    [ "$(cat "$outfile")" = "/my/key" ]
}

@test "run_hook: expands {container} placeholder" {
    local outfile="$TMPDIR/out"
    run_hook "on-enter" "echo {container} > '$outfile'" "1234" "/key" "test-vm" "/work"
    [ "$(cat "$outfile")" = "test-vm" ]
}

@test "run_hook: expands {workdir} placeholder" {
    local outfile="$TMPDIR/out"
    run_hook "on-enter" "echo {workdir} > '$outfile'" "1234" "/key" "myvm" "/my/workdir"
    [ "$(cat "$outfile")" = "/my/workdir" ]
}

@test "run_hook: expands all placeholders in one command" {
    local outfile="$TMPDIR/out"
    run_hook "on-enter" \
        "echo {ssh_port} {ssh_key} {container} {workdir} > '$outfile'" \
        "9999" "/ssh/key" "vm1" "/home/user/code"
    [ "$(cat "$outfile")" = "9999 /ssh/key vm1 /home/user/code" ]
}

@test "run_hook: exports SCHUPFN_SSH_PORT" {
    local outfile="$TMPDIR/out"
    run_hook "on-enter" 'echo $SCHUPFN_SSH_PORT > '"'$outfile'" "4242" "/key" "myvm" "/work"
    [ "$(cat "$outfile")" = "4242" ]
}

@test "run_hook: exports SCHUPFN_SSH_KEY" {
    local outfile="$TMPDIR/out"
    run_hook "on-enter" 'echo $SCHUPFN_SSH_KEY > '"'$outfile'" "1234" "/path/to/key" "myvm" "/work"
    [ "$(cat "$outfile")" = "/path/to/key" ]
}

@test "run_hook: exports SCHUPFN_CONTAINER" {
    local outfile="$TMPDIR/out"
    run_hook "on-enter" 'echo $SCHUPFN_CONTAINER > '"'$outfile'" "1234" "/key" "my-vm" "/work"
    [ "$(cat "$outfile")" = "my-vm" ]
}

@test "run_hook: exports SCHUPFN_WORKDIR" {
    local outfile="$TMPDIR/out"
    run_hook "on-enter" 'echo $SCHUPFN_WORKDIR > '"'$outfile'" "1234" "/key" "myvm" "/the/workdir"
    [ "$(cat "$outfile")" = "/the/workdir" ]
}

@test "run_hook: warns on non-zero exit" {
    run_hook "on-exit" "false" "1234" "/key" "myvm" "/work"
    assert_warned "on-exit hook exited with status"
}

@test "run_hook: no warning on success" {
    run_hook "on-enter" "true" "1234" "/key" "myvm" "/work"
    assert_no_warnings
}

@test "run_hook: command without placeholders runs as-is" {
    local outfile="$TMPDIR/out"
    run_hook "on-enter" "echo hello > '$outfile'" "1234" "/key" "myvm" "/work"
    [ "$(cat "$outfile")" = "hello" ]
}

@test "run_hook: env vars do not leak into parent shell" {
    unset SCHUPFN_SSH_PORT SCHUPFN_SSH_KEY SCHUPFN_CONTAINER SCHUPFN_WORKDIR
    run_hook "on-enter" "true" "1234" "/key" "myvm" "/work"
    [ -z "${SCHUPFN_SSH_PORT:-}" ]
    [ -z "${SCHUPFN_SSH_KEY:-}" ]
    [ -z "${SCHUPFN_CONTAINER:-}" ]
    [ -z "${SCHUPFN_WORKDIR:-}" ]
}

# ── load_config: hook fields ────────────────────────────────────────────────

# Skip the whole file if yq isn't available
yq_or_skip() {
    command -v yq >/dev/null 2>&1 || skip "yq not installed"
}

# Initialize the variables that load_config writes to
init_cfg_vars() {
    _cfg_container=""
    _cfg_command=""
    _cfg_exports=()
    _cfg_exports_rw=()
    _cfg_exports_cow=()
    _cfg_memory=""
    _cfg_cpus=""
    _cfg_network=""
    _cfg_display=""
    _cfg_follow_git_worktrees=""
    _cfg_image_size=""
    _cfg_packages=()
    _cfg_env=()
    _cfg_on_enter=""
    _cfg_on_exit=""
    _cfg_on_join=""
    _cfg_on_leave=""
}

@test "load_config: parses on-enter hook" {
    yq_or_skip
    init_cfg_vars
    cat > "$TMPDIR/config.yml" <<'EOF'
on-enter: "my-script.sh in"
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_on_enter" = "my-script.sh in" ]
}

@test "load_config: parses on-exit hook" {
    yq_or_skip
    init_cfg_vars
    cat > "$TMPDIR/config.yml" <<'EOF'
on-exit: "my-script.sh out"
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_on_exit" = "my-script.sh out" ]
}

@test "load_config: parses on-join hook" {
    yq_or_skip
    init_cfg_vars
    cat > "$TMPDIR/config.yml" <<'EOF'
on-join: "echo joined"
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_on_join" = "echo joined" ]
}

@test "load_config: parses on-leave hook" {
    yq_or_skip
    init_cfg_vars
    cat > "$TMPDIR/config.yml" <<'EOF'
on-leave: "echo left"
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_on_leave" = "echo left" ]
}

@test "load_config: hook fields default to empty" {
    yq_or_skip
    init_cfg_vars
    cat > "$TMPDIR/config.yml" <<'EOF'
container: my-toolbox
EOF
    load_config "$TMPDIR/config.yml"
    [ -z "$_cfg_on_enter" ]
    [ -z "$_cfg_on_exit" ]
    [ -z "$_cfg_on_join" ]
    [ -z "$_cfg_on_leave" ]
}

@test "load_config: hook with placeholders preserved literally" {
    yq_or_skip
    init_cfg_vars
    cat > "$TMPDIR/config.yml" <<'EOF'
on-enter: "sync.sh {ssh_port} {ssh_key} {container} {workdir}"
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_on_enter" = "sync.sh {ssh_port} {ssh_key} {container} {workdir}" ]
}

@test "load_config: all four hooks in one config" {
    yq_or_skip
    init_cfg_vars
    cat > "$TMPDIR/config.yml" <<'EOF'
on-enter: "enter-cmd"
on-exit: "exit-cmd"
on-join: "join-cmd"
on-leave: "leave-cmd"
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_on_enter" = "enter-cmd" ]
    [ "$_cfg_on_exit" = "exit-cmd" ]
    [ "$_cfg_on_join" = "join-cmd" ]
    [ "$_cfg_on_leave" = "leave-cmd" ]
}

@test "load_config: no unknown key warning for hook fields" {
    yq_or_skip
    init_cfg_vars
    cat > "$TMPDIR/config.yml" <<'EOF'
on-enter: "cmd1"
on-exit: "cmd2"
on-join: "cmd3"
on-leave: "cmd4"
EOF
    load_config "$TMPDIR/config.yml"
    assert_no_warnings
}

# ── load_config: env ────────────────────────────────────────────────────────

@test "load_config: parses env variables" {
    yq_or_skip
    init_cfg_vars
    cat > "$TMPDIR/config.yml" <<'EOF'
env:
  MY_VAR: hello
  OTHER_VAR: world
EOF
    load_config "$TMPDIR/config.yml"
    [ ${#_cfg_env[@]} -eq 2 ]
    [[ " ${_cfg_env[*]} " == *" MY_VAR=hello "* ]]
    [[ " ${_cfg_env[*]} " == *" OTHER_VAR=world "* ]]
}

@test "load_config: env defaults to empty" {
    yq_or_skip
    init_cfg_vars
    cat > "$TMPDIR/config.yml" <<'EOF'
container: my-toolbox
EOF
    load_config "$TMPDIR/config.yml"
    [ ${#_cfg_env[@]} -eq 0 ]
}

@test "load_config: no unknown key warning for env" {
    yq_or_skip
    init_cfg_vars
    cat > "$TMPDIR/config.yml" <<'EOF'
env:
  FOO: bar
EOF
    load_config "$TMPDIR/config.yml"
    assert_no_warnings
}

@test "load_config: env with numeric value" {
    yq_or_skip
    init_cfg_vars
    cat > "$TMPDIR/config.yml" <<'EOF'
env:
  PORT: 8080
EOF
    load_config "$TMPDIR/config.yml"
    [ ${#_cfg_env[@]} -eq 1 ]
    [ "${_cfg_env[0]}" = "PORT=8080" ]
}

@test "run_hook: exports env: config variables" {
    _cfg_env=(MY_VAR=hello OTHER_VAR=world)
    local outfile="$TMPDIR/out"
    run_hook "on-enter" 'echo $MY_VAR $OTHER_VAR > '"'$outfile'" "1234" "/key" "myvm" "/work" "test-uuid"
    [ "$(cat "$outfile")" = "hello world" ]
}

@test "run_hook: env: config variables do not leak into parent shell" {
    _cfg_env=(MY_VAR=hello)
    unset MY_VAR 2>/dev/null || true
    run_hook "on-enter" "true" "1234" "/key" "myvm" "/work" "test-uuid"
    [ -z "${MY_VAR:-}" ]
}

@test "run_hook: expands placeholders in env: values" {
    _cfg_env=("SYNC_DIR={workdir}/.sync/{uuid}")
    local outfile="$TMPDIR/out"
    run_hook "on-enter" 'echo $SYNC_DIR > '"'$outfile'" "1234" "/key" "myvm" "/my/work" "abc-uuid"
    [ "$(cat "$outfile")" = "/my/work/.sync/abc-uuid" ]
}

@test "run_hook: env keys available as placeholders in command" {
    _cfg_env=("FOOBAR=abc")
    local outfile="$TMPDIR/out"
    run_hook "on-enter" "echo {FOOBAR} > '$outfile'" "1234" "/key" "myvm" "/work" "test-uuid"
    [ "$(cat "$outfile")" = "abc" ]
}

@test "run_hook: env key placeholder with resolved value" {
    _cfg_env=("SYNC_DIR={workdir}/.sync/{uuid}")
    local outfile="$TMPDIR/out"
    run_hook "on-enter" "echo {SYNC_DIR} > '$outfile'" "1234" "/key" "myvm" "/my/work" "abc-uuid"
    [ "$(cat "$outfile")" = "/my/work/.sync/abc-uuid" ]
}

@test "run_hook: works without _cfg_env in scope" {
    unset _cfg_env 2>/dev/null || true
    local outfile="$TMPDIR/out"
    run_hook "on-enter" "echo ok > '$outfile'" "1234" "/key" "myvm" "/work" "test-uuid"
    [ "$(cat "$outfile")" = "ok" ]
}
