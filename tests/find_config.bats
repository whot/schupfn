#!/usr/bin/env bats

load test_helper

setup() {
    reset_die
    TMPDIR="$(make_tmpdir)"
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
