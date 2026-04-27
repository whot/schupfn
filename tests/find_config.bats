#!/usr/bin/env bats

load test_helper

setup() {
    reset_die
    TMPDIR="$(make_tmpdir)"
    # Resolve symlinks (e.g. /tmp -> /private/tmp on macOS) so expected
    # paths match the realpath output from find_config_file().
    TMPDIR="$(realpath "$TMPDIR")"
    # Prevent the XDG fallback from finding a real config on the host.
    # Tests that exercise the XDG path set this to their own value.
    export XDG_CONFIG_HOME="$TMPDIR/xdg-config-none"
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "find_config_file: finds config in current directory" {
    mkdir -p "$TMPDIR/.schupfn"
    echo "container: test" > "$TMPDIR/.schupfn/config.yml"

    run find_config_file "$TMPDIR"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR/.schupfn/config.yml" ]
}

@test "find_config_file: finds config in parent directory" {
    mkdir -p "$TMPDIR/.schupfn"
    echo "container: test" > "$TMPDIR/.schupfn/config.yml"
    mkdir -p "$TMPDIR/child/grandchild"

    run find_config_file "$TMPDIR/child/grandchild"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR/.schupfn/config.yml" ]
}

@test "find_config_file: closer config wins over parent" {
    mkdir -p "$TMPDIR/.schupfn"
    echo "container: parent" > "$TMPDIR/.schupfn/config.yml"
    mkdir -p "$TMPDIR/child/.schupfn"
    echo "container: child" > "$TMPDIR/child/.schupfn/config.yml"

    run find_config_file "$TMPDIR/child"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR/child/.schupfn/config.yml" ]
}

@test "find_config_file: returns 1 when no config exists" {
    mkdir -p "$TMPDIR/a/b/c"

    run find_config_file "$TMPDIR/a/b/c"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "find_config_file: ignores wrong filenames" {
    mkdir -p "$TMPDIR/.schupfn"
    # config.yaml instead of config.yml
    echo "container: test" > "$TMPDIR/.schupfn/config.yaml"

    run find_config_file "$TMPDIR"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "find_config_file: ignores .schupfn if it is a file not a directory" {
    touch "$TMPDIR/.schupfn"

    run find_config_file "$TMPDIR"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "find_config_file: handles directory names with spaces" {
    mkdir -p "$TMPDIR/my project/.schupfn"
    echo "container: test" > "$TMPDIR/my project/.schupfn/config.yml"

    run find_config_file "$TMPDIR/my project"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR/my project/.schupfn/config.yml" ]
}

@test "find_config_file: works when starting from / (no infinite loop)" {
    # This just verifies it terminates and returns 1 (no config at /).
    # If there happens to be a /.schupfn/config.yml on the host we
    # can't control that, so just check it terminates.
    run find_config_file "/"
    # status is 0 or 1, either is fine, just shouldn't hang
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

# ── XDG_CONFIG_HOME fallback tests ──────────────────────────────────────────

@test "find_config_file: falls back to XDG_CONFIG_HOME/schupfn/default-config.yml" {
    mkdir -p "$TMPDIR/xdg-config/schupfn"
    echo "container: default" > "$TMPDIR/xdg-config/schupfn/default-config.yml"
    mkdir -p "$TMPDIR/project"

    XDG_CONFIG_HOME="$TMPDIR/xdg-config" run find_config_file "$TMPDIR/project"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR/xdg-config/schupfn/default-config.yml" ]
}

@test "find_config_file: local config takes precedence over XDG fallback" {
    mkdir -p "$TMPDIR/xdg-config/schupfn"
    echo "container: default" > "$TMPDIR/xdg-config/schupfn/default-config.yml"
    mkdir -p "$TMPDIR/project/.schupfn"
    echo "container: local" > "$TMPDIR/project/.schupfn/config.yml"

    XDG_CONFIG_HOME="$TMPDIR/xdg-config" run find_config_file "$TMPDIR/project"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR/project/.schupfn/config.yml" ]
}

@test "find_config_file: returns 1 when no local config and no XDG fallback" {
    mkdir -p "$TMPDIR/project"

    XDG_CONFIG_HOME="$TMPDIR/nonexistent" run find_config_file "$TMPDIR/project"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "find_config_file: falls back to ~/.config when XDG_CONFIG_HOME is unset" {
    # Use a fake HOME to avoid interfering with the real one
    local fake_home="$TMPDIR/fakehome"
    mkdir -p "$fake_home/.config/schupfn"
    echo "container: home-default" > "$fake_home/.config/schupfn/default-config.yml"
    mkdir -p "$TMPDIR/project"

    HOME="$fake_home" XDG_CONFIG_HOME="" run find_config_file "$TMPDIR/project"
    [ "$status" -eq 0 ]
    [ "$output" = "$fake_home/.config/schupfn/default-config.yml" ]
}

# ── Container-specific XDG config tests ─────────────────────────────────────

@test "find_config_file: uses container-specific XDG config when available" {
    mkdir -p "$TMPDIR/xdg-config/schupfn"
    echo "container: mybox" > "$TMPDIR/xdg-config/schupfn/mybox-config.yml"
    echo "container: default" > "$TMPDIR/xdg-config/schupfn/default-config.yml"
    mkdir -p "$TMPDIR/project"

    XDG_CONFIG_HOME="$TMPDIR/xdg-config" run find_config_file "$TMPDIR/project" "mybox"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR/xdg-config/schupfn/mybox-config.yml" ]
}

@test "find_config_file: falls back to default-config.yml when container-specific config missing" {
    mkdir -p "$TMPDIR/xdg-config/schupfn"
    echo "container: default" > "$TMPDIR/xdg-config/schupfn/default-config.yml"
    mkdir -p "$TMPDIR/project"

    XDG_CONFIG_HOME="$TMPDIR/xdg-config" run find_config_file "$TMPDIR/project" "mybox"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR/xdg-config/schupfn/default-config.yml" ]
}

@test "find_config_file: container-specific config without default-config.yml" {
    mkdir -p "$TMPDIR/xdg-config/schupfn"
    echo "container: mybox" > "$TMPDIR/xdg-config/schupfn/mybox-config.yml"
    mkdir -p "$TMPDIR/project"

    XDG_CONFIG_HOME="$TMPDIR/xdg-config" run find_config_file "$TMPDIR/project" "mybox"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR/xdg-config/schupfn/mybox-config.yml" ]
}

@test "find_config_file: local config takes precedence over container-specific XDG config" {
    mkdir -p "$TMPDIR/xdg-config/schupfn"
    echo "container: mybox" > "$TMPDIR/xdg-config/schupfn/mybox-config.yml"
    mkdir -p "$TMPDIR/project/.schupfn"
    echo "container: local" > "$TMPDIR/project/.schupfn/config.yml"

    XDG_CONFIG_HOME="$TMPDIR/xdg-config" run find_config_file "$TMPDIR/project" "mybox"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR/project/.schupfn/config.yml" ]
}

@test "find_config_file: empty container name skips container-specific lookup" {
    mkdir -p "$TMPDIR/xdg-config/schupfn"
    echo "container: default" > "$TMPDIR/xdg-config/schupfn/default-config.yml"
    # This file should never match with an empty name
    echo "container: empty" > "$TMPDIR/xdg-config/schupfn/-config.yml"
    mkdir -p "$TMPDIR/project"

    XDG_CONFIG_HOME="$TMPDIR/xdg-config" run find_config_file "$TMPDIR/project" ""
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR/xdg-config/schupfn/default-config.yml" ]
}

@test "find_config_file: returns 1 when no local, no container-specific, no default" {
    mkdir -p "$TMPDIR/project"

    XDG_CONFIG_HOME="$TMPDIR/nonexistent" run find_config_file "$TMPDIR/project" "mybox"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

# ── Symlink handling tests ──────────────────────────────────────────────────

@test "find_config_file: finds config via symlink when PWD is a symlink to project" {
    # Real project with a config
    mkdir -p "$TMPDIR/real-project/.schupfn"
    echo "container: real" > "$TMPDIR/real-project/.schupfn/config.yml"

    # Symlink pointing to the project — the logical walk finds the config
    # through the symlink, but the returned path is resolved to the
    # canonical physical path so callers always get a consistent result.
    ln -s "$TMPDIR/real-project" "$TMPDIR/link-to-project"

    run find_config_file "$TMPDIR/link-to-project"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR/real-project/.schupfn/config.yml" ]
}

@test "find_config_file: finds config in physical parent when symlink is to subdirectory" {
    # Real project with a config
    mkdir -p "$TMPDIR/real-project/.schupfn"
    echo "container: real" > "$TMPDIR/real-project/.schupfn/config.yml"
    mkdir -p "$TMPDIR/real-project/subdir"

    # Symlink pointing to a subdirectory
    ln -s "$TMPDIR/real-project/subdir" "$TMPDIR/link-to-subdir"

    run find_config_file "$TMPDIR/link-to-subdir"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR/real-project/.schupfn/config.yml" ]
}
