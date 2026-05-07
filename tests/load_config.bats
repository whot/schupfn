#!/usr/bin/env bats

load test_helper

setup() {
    reset_die
    TMPDIR="$(make_tmpdir)"

    # Initialize the variables that load_config writes to,
    # matching what cmd_enter does before calling load_config.
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
}

teardown() {
    rm -rf "$TMPDIR"
}

# Skip the whole file if yq isn't available
yq_or_skip() {
    command -v yq >/dev/null 2>&1 || skip "yq not installed"
}

@test "load_config: parses container field" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
container: my-toolbox
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_container" = "my-toolbox" ]
}

@test "load_config: parses command field" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
command: make test
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_command" = "make test" ]
}

@test "load_config: parses export-ro list" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
export-ro:
  - /tmp/aaa
  - /tmp/bbb
EOF
    load_config "$TMPDIR/config.yml"
    [ "${#_cfg_exports[@]}" -eq 2 ]
    [ "${_cfg_exports[0]}" = "/tmp/aaa" ]
    [ "${_cfg_exports[1]}" = "/tmp/bbb" ]
}

@test "load_config: parses export-rw list" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
export-rw:
  - /tmp/xxx
  - /tmp/yyy
EOF
    load_config "$TMPDIR/config.yml"
    [ "${#_cfg_exports_rw[@]}" -eq 2 ]
    [ "${_cfg_exports_rw[0]}" = "/tmp/xxx" ]
    [ "${_cfg_exports_rw[1]}" = "/tmp/yyy" ]
}

@test "load_config: parses export-cow list" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
export-cow:
  - /tmp/cow1
  - /tmp/cow2
EOF
    load_config "$TMPDIR/config.yml"
    [ "${#_cfg_exports_cow[@]}" -eq 2 ]
    [ "${_cfg_exports_cow[0]}" = "/tmp/cow1" ]
    [ "${_cfg_exports_cow[1]}" = "/tmp/cow2" ]
}

@test "load_config: parses vm.memory" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
vm:
  memory: 8G
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_memory" = "8G" ]
}

@test "load_config: parses vm.cpus" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
vm:
  cpus: 4
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_cpus" = "4" ]
}

@test "load_config: vm.network false sets _cfg_network to 0" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
vm:
  network: false
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_network" = "0" ]
}

@test "load_config: vm.network true leaves _cfg_network empty" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
vm:
  network: true
EOF
    load_config "$TMPDIR/config.yml"
    [ -z "$_cfg_network" ]
}

@test "load_config: follow-git-worktrees true sets _cfg_follow_git_worktrees to 1" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
follow-git-worktrees: true
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_follow_git_worktrees" = "1" ]
}

@test "load_config: follow-git-worktrees false leaves _cfg_follow_git_worktrees empty" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
follow-git-worktrees: false
EOF
    load_config "$TMPDIR/config.yml"
    [ -z "$_cfg_follow_git_worktrees" ]
}

@test "load_config: parses image.size" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
image:
  size: 10G
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_image_size" = "10G" ]
}

@test "load_config: parses image.install-packages" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
image:
  install-packages:
    - zsh
    - vim
    - htop
EOF
    load_config "$TMPDIR/config.yml"
    [ "${#_cfg_packages[@]}" -eq 3 ]
    [ "${_cfg_packages[0]}" = "zsh" ]
    [ "${_cfg_packages[1]}" = "vim" ]
    [ "${_cfg_packages[2]}" = "htop" ]
}

@test "load_config: parses vm.display" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
vm:
  display: virtio
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_display" = "virtio" ]
}

@test "load_config: warns on obsolete ssh_key field" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
ssh_key: ~/.ssh/test_key
EOF
    load_config "$TMPDIR/config.yml"
    assert_warned "unknown config key 'ssh_key'"
}

@test "load_config: dies on invalid YAML" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
this is: [not: valid: yaml
EOF
    load_config "$TMPDIR/config.yml" || true
    assert_die_called "failed to parse"
}

@test "load_config: empty config file produces all defaults" {
    yq_or_skip
    touch "$TMPDIR/config.yml"
    load_config "$TMPDIR/config.yml"
    [ -z "$_cfg_container" ]
    [ -z "$_cfg_command" ]
    [ "${#_cfg_exports[@]}" -eq 0 ]
    [ "${#_cfg_exports_rw[@]}" -eq 0 ]
    [ "${#_cfg_exports_cow[@]}" -eq 0 ]
    [ -z "$_cfg_display" ]
    [ -z "$_cfg_follow_git_worktrees" ]
    [ -z "$_cfg_image_size" ]
    [ -z "$_cfg_memory" ]
    [ -z "$_cfg_cpus" ]
    [ -z "$_cfg_network" ]
}

@test "load_config: missing keys produce empty defaults" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
container: only-this
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_container" = "only-this" ]
    [ -z "$_cfg_command" ]
    [ "${#_cfg_exports[@]}" -eq 0 ]
    [ -z "$_cfg_memory" ]
}

@test "load_config: full config with all fields" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
container: full-test
command: ./run.sh
export-ro:
  - /tmp/ro1
export-rw:
  - /tmp/rw1
export-cow:
  - /tmp/cow1
follow-git-worktrees: true
image:
  size: 10G
  install-packages:
    - zsh
    - vim
vm:
  memory: 16G
  cpus: 8
  network: false
  display: virtio
EOF
    load_config "$TMPDIR/config.yml"
    [ "$_cfg_container" = "full-test" ]
    [ "$_cfg_command" = "./run.sh" ]
    [ "${#_cfg_exports[@]}" -eq 1 ]
    [ "${_cfg_exports[0]}" = "/tmp/ro1" ]
    [ "${#_cfg_exports_rw[@]}" -eq 1 ]
    [ "${_cfg_exports_rw[0]}" = "/tmp/rw1" ]
    [ "${#_cfg_exports_cow[@]}" -eq 1 ]
    [ "${_cfg_exports_cow[0]}" = "/tmp/cow1" ]
    [ "$_cfg_follow_git_worktrees" = "1" ]
    [ "$_cfg_image_size" = "10G" ]
    [ "${#_cfg_packages[@]}" -eq 2 ]
    [ "${_cfg_packages[0]}" = "zsh" ]
    [ "${_cfg_packages[1]}" = "vim" ]
    [ "$_cfg_memory" = "16G" ]
    [ "$_cfg_cpus" = "8" ]
    [ "$_cfg_network" = "0" ]
    [ "$_cfg_display" = "virtio" ]
}

@test "load_config: warns on unknown top-level key" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
container: my-toolbox
bogus: hello
EOF
    load_config "$TMPDIR/config.yml"
    assert_warned "unknown config key 'bogus'"
}

@test "load_config: warns on unknown nested vm key" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
vm:
  memory: 4G
  disks: 2
EOF
    load_config "$TMPDIR/config.yml"
    assert_warned "unknown config key 'vm.disks'"
}

@test "load_config: warns on multiple unknown keys" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
contaner: typo
vm:
  memorry: 8G
EOF
    load_config "$TMPDIR/config.yml"
    assert_warned "unknown config key 'contaner'"
    assert_warned "unknown config key 'vm.memorry'"
}

@test "load_config: no warnings for valid config" {
    yq_or_skip
    cat > "$TMPDIR/config.yml" <<'EOF'
container: my-toolbox
command: make test
export-ro:
  - /tmp/aaa
export-rw:
  - /tmp/bbb
export-cow:
  - /tmp/ccc
follow-git-worktrees: true
image:
  size: 10G
  install-packages:
    - zsh
vm:
  memory: 4G
  cpus: 2
  network: false
  display: virtio
EOF
    load_config "$TMPDIR/config.yml"
    assert_no_warnings
}

@test "load_config: no warnings for empty config" {
    yq_or_skip
    touch "$TMPDIR/config.yml"
    load_config "$TMPDIR/config.yml"
    assert_no_warnings
}
