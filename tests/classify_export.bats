#!/usr/bin/env bats

load test_helper

setup() {
    reset_die
    TMPDIR="$(make_tmpdir)"

    # Initialize the arrays that classify_export appends to,
    # matching what cmd_enter does before the classify loop.
    rw_mount_dirs=()
    ro_mount_dirs=()
    cow_mount_dirs=()
    rootfs_symlinks=()
    dotfiles=()
}

teardown() {
    rm -rf "$TMPDIR"
}

# ── Directories ──────────────────────────────────────────────────────────

@test "classify_export: directory with mode ro goes to ro_mount_dirs" {
    mkdir -p "$TMPDIR/mydir"

    classify_export "$TMPDIR/mydir" "ro"
    assert_die_not_called
    [ "${#ro_mount_dirs[@]}" -eq 1 ]
    [ "${ro_mount_dirs[0]}" = "$(realpath "$TMPDIR/mydir")" ]
    [ "${#rw_mount_dirs[@]}" -eq 0 ]
}

@test "classify_export: directory with mode rw goes to rw_mount_dirs" {
    mkdir -p "$TMPDIR/mydir"

    classify_export "$TMPDIR/mydir" "rw"
    assert_die_not_called
    [ "${#rw_mount_dirs[@]}" -eq 1 ]
    [ "${rw_mount_dirs[0]}" = "$(realpath "$TMPDIR/mydir")" ]
    [ "${#ro_mount_dirs[@]}" -eq 0 ]
}

@test "classify_export: directory with mode cow goes to cow_mount_dirs" {
    mkdir -p "$TMPDIR/mydir"

    classify_export "$TMPDIR/mydir" "cow"
    assert_die_not_called
    [ "${#cow_mount_dirs[@]}" -eq 1 ]
    [ "${cow_mount_dirs[0]}" = "$(realpath "$TMPDIR/mydir")" ]
    [ "${#rw_mount_dirs[@]}" -eq 0 ]
    [ "${#ro_mount_dirs[@]}" -eq 0 ]
}

# ── Files ────────────────────────────────────────────────────────────────

@test "classify_export: regular file goes to dotfiles (mode ro)" {
    touch "$TMPDIR/myfile"

    classify_export "$TMPDIR/myfile" "ro"
    assert_die_not_called
    [ "${#dotfiles[@]}" -eq 1 ]
    [ "${dotfiles[0]}" = "$(realpath "$TMPDIR/myfile")" ]
    [ "${#ro_mount_dirs[@]}" -eq 0 ]
    [ "${#rw_mount_dirs[@]}" -eq 0 ]
}

@test "classify_export: regular file goes to dotfiles (mode rw)" {
    touch "$TMPDIR/myfile"

    classify_export "$TMPDIR/myfile" "rw"
    assert_die_not_called
    [ "${#dotfiles[@]}" -eq 1 ]
    [ "${dotfiles[0]}" = "$(realpath "$TMPDIR/myfile")" ]
}

@test "classify_export: cow mode rejects files" {
    touch "$TMPDIR/myfile"

    classify_export "$TMPDIR/myfile" "cow" || true
    assert_die_called
}

# ── Symlinks ─────────────────────────────────────────────────────────────

@test "classify_export: symlink to directory goes to mount_dirs and produces symlink entry" {
    mkdir -p "$TMPDIR/realdir"
    ln -s "$TMPDIR/realdir" "$TMPDIR/linkdir"

    classify_export "$TMPDIR/linkdir" "ro"
    assert_die_not_called
    [ "${#ro_mount_dirs[@]}" -eq 1 ]
    [ "${ro_mount_dirs[0]}" = "$(realpath "$TMPDIR/realdir")" ]
    [ "${#rootfs_symlinks[@]}" -eq 1 ]
    # The symlink entry is "logical_path:resolved_path"
    [[ "${rootfs_symlinks[0]}" == *":$(realpath "$TMPDIR/realdir")" ]]
}

@test "classify_export: symlink to file goes to dotfiles with link path" {
    touch "$TMPDIR/realfile"
    ln -s "$TMPDIR/realfile" "$TMPDIR/linkfile"

    classify_export "$TMPDIR/linkfile" "ro"
    assert_die_not_called
    [ "${#dotfiles[@]}" -eq 1 ]
    [ "${dotfiles[0]}" = "$TMPDIR/linkfile" ]
}

# ── Error cases ──────────────────────────────────────────────────────────

@test "classify_export: nonexistent path calls die" {
    classify_export "$TMPDIR/does-not-exist" "ro" || true
    assert_die_called "does not exist"
}

# ── Tilde expansion ─────────────────────────────────────────────────────

@test "classify_export: expands tilde in path" {
    local saved_home="$HOME"
    export HOME="$TMPDIR"
    mkdir -p "$TMPDIR/somedir"

    classify_export "~/somedir" "rw"
    assert_die_not_called
    [ "${#rw_mount_dirs[@]}" -eq 1 ]
    [ "${rw_mount_dirs[0]}" = "$(realpath "$TMPDIR/somedir")" ]
    export HOME="$saved_home"
}

# ── Multiple calls accumulate ────────────────────────────────────────────

@test "classify_export: multiple calls accumulate into arrays" {
    mkdir -p "$TMPDIR/dir1" "$TMPDIR/dir2"
    touch "$TMPDIR/file1" "$TMPDIR/file2"

    classify_export "$TMPDIR/dir1" "ro"
    classify_export "$TMPDIR/dir2" "rw"
    classify_export "$TMPDIR/file1" "ro"
    classify_export "$TMPDIR/file2" "rw"

    assert_die_not_called
    [ "${#ro_mount_dirs[@]}" -eq 1 ]
    [ "${#rw_mount_dirs[@]}" -eq 1 ]
    [ "${#dotfiles[@]}" -eq 2 ]
}

# ── check_nested_export_conflicts ────────────────────────────────────────

@test "check_nested_export_conflicts: rw child inside ro parent errors" {
    mkdir -p "$TMPDIR/foo/bar"

    classify_export "$TMPDIR/foo" "ro"
    classify_export "$TMPDIR/foo/bar" "rw"
    assert_die_not_called

    check_nested_export_conflicts || true
    assert_die_called "conflicting exports"
    assert_die_called "nested inside"
}

@test "check_nested_export_conflicts: ro child inside rw parent errors" {
    mkdir -p "$TMPDIR/foo/bar"

    classify_export "$TMPDIR/foo" "rw"
    classify_export "$TMPDIR/foo/bar" "ro"
    assert_die_not_called

    check_nested_export_conflicts || true
    assert_die_called "conflicting exports"
    assert_die_called "nested inside"
}

@test "check_nested_export_conflicts: non-overlapping dirs are fine" {
    mkdir -p "$TMPDIR/aaa" "$TMPDIR/bbb"

    classify_export "$TMPDIR/aaa" "ro"
    classify_export "$TMPDIR/bbb" "rw"
    assert_die_not_called

    check_nested_export_conflicts || true
    assert_die_not_called
}

@test "check_nested_export_conflicts: same mode nesting is fine" {
    mkdir -p "$TMPDIR/foo/bar"

    classify_export "$TMPDIR/foo" "ro"
    classify_export "$TMPDIR/foo/bar" "ro"
    assert_die_not_called

    check_nested_export_conflicts || true
    assert_die_not_called
}

@test "check_nested_export_conflicts: similarly named dirs are not nested" {
    mkdir -p "$TMPDIR/foobar" "$TMPDIR/foo"

    classify_export "$TMPDIR/foo" "ro"
    classify_export "$TMPDIR/foobar" "rw"
    assert_die_not_called

    check_nested_export_conflicts || true
    assert_die_not_called
}

@test "check_nested_export_conflicts: same path as ro and rw errors" {
    mkdir -p "$TMPDIR/foo"

    classify_export "$TMPDIR/foo" "ro"
    classify_export "$TMPDIR/foo" "rw"
    assert_die_not_called

    check_nested_export_conflicts || true
    assert_die_called "conflicting exports"
}

@test "check_nested_export_conflicts: root ro parent catches rw child" {
    # Bypass classify_export to avoid realpath on dirs we may not own;
    # inject "/" and a child path directly into the arrays.
    ro_mount_dirs=("/")
    rw_mount_dirs=("/child")
    assert_die_not_called

    check_nested_export_conflicts || true
    assert_die_called "conflicting exports"
    assert_die_called "nested inside"
}

@test "check_nested_export_conflicts: cow child inside ro parent errors" {
    mkdir -p "$TMPDIR/foo/bar"

    classify_export "$TMPDIR/foo" "ro"
    classify_export "$TMPDIR/foo/bar" "cow"
    assert_die_not_called

    check_nested_export_conflicts || true
    assert_die_called "conflicting exports"
    assert_die_called "nested inside"
}

@test "check_nested_export_conflicts: same path as ro and cow errors" {
    mkdir -p "$TMPDIR/foo"

    classify_export "$TMPDIR/foo" "ro"
    classify_export "$TMPDIR/foo" "cow"
    assert_die_not_called

    check_nested_export_conflicts || true
    assert_die_called "conflicting exports"
}

@test "check_nested_export_conflicts: non-overlapping cow and rw are fine" {
    mkdir -p "$TMPDIR/aaa" "$TMPDIR/bbb"

    classify_export "$TMPDIR/aaa" "cow"
    classify_export "$TMPDIR/bbb" "rw"
    assert_die_not_called

    check_nested_export_conflicts || true
    assert_die_not_called
}

# ── pwd_covered_by_export ────────────────────────────────────────────────

@test "pwd_covered_by_export: pwd matches rw export exactly" {
    mkdir -p "$TMPDIR/mydir"
    rw_mount_dirs=("$(realpath "$TMPDIR/mydir")")

    local mode
    mode=$(pwd_covered_by_export "$(realpath "$TMPDIR/mydir")")
    [ "$mode" = "rw" ]
}

@test "pwd_covered_by_export: pwd matches ro export exactly" {
    mkdir -p "$TMPDIR/mydir"
    ro_mount_dirs=("$(realpath "$TMPDIR/mydir")")

    local mode
    mode=$(pwd_covered_by_export "$(realpath "$TMPDIR/mydir")")
    [ "$mode" = "ro" ]
}

@test "pwd_covered_by_export: pwd matches cow export exactly" {
    mkdir -p "$TMPDIR/mydir"
    cow_mount_dirs=("$(realpath "$TMPDIR/mydir")")

    local mode
    mode=$(pwd_covered_by_export "$(realpath "$TMPDIR/mydir")")
    [ "$mode" = "cow" ]
}

@test "pwd_covered_by_export: pwd is subdirectory of rw export" {
    mkdir -p "$TMPDIR/parent/child"
    rw_mount_dirs=("$(realpath "$TMPDIR/parent")")

    local mode
    mode=$(pwd_covered_by_export "$(realpath "$TMPDIR/parent/child")")
    [ "$mode" = "rw" ]
}

@test "pwd_covered_by_export: pwd is subdirectory of ro export" {
    mkdir -p "$TMPDIR/parent/child"
    ro_mount_dirs=("$(realpath "$TMPDIR/parent")")

    local mode
    mode=$(pwd_covered_by_export "$(realpath "$TMPDIR/parent/child")")
    [ "$mode" = "ro" ]
}

@test "pwd_covered_by_export: pwd is not inside any export" {
    mkdir -p "$TMPDIR/exported" "$TMPDIR/elsewhere"
    rw_mount_dirs=("$(realpath "$TMPDIR/exported")")

    run pwd_covered_by_export "$(realpath "$TMPDIR/elsewhere")"
    [ "$status" -eq 1 ]
}

@test "pwd_covered_by_export: similarly named dir is not a match" {
    mkdir -p "$TMPDIR/foobar" "$TMPDIR/foo"
    rw_mount_dirs=("$(realpath "$TMPDIR/foo")")

    run pwd_covered_by_export "$(realpath "$TMPDIR/foobar")"
    [ "$status" -eq 1 ]
}

@test "pwd_covered_by_export: no exports returns failure" {
    mkdir -p "$TMPDIR/mydir"

    run pwd_covered_by_export "$(realpath "$TMPDIR/mydir")"
    [ "$status" -eq 1 ]
}

@test "pwd_covered_by_export: root export covers everything" {
    rw_mount_dirs=("/")

    local mode
    mode=$(pwd_covered_by_export "/some/deep/path")
    [ "$mode" = "rw" ]
}
