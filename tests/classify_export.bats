#!/usr/bin/env bats

load test_helper

setup() {
    reset_die
    TMPDIR="$(make_tmpdir)"

    # Initialize the arrays that classify_export appends to,
    # matching what cmd_enter does before the classify loop.
    rw_mount_dirs=()
    ro_mount_dirs=()
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

# ── add_overlay ──────────────────────────────────────────────────────────

@test "add_overlay: extracts top-level directory" {
    local -a overlay_dirs=()
    add_overlay "/home/user/project"
    [ "${#overlay_dirs[@]}" -eq 1 ]
    [ "${overlay_dirs[0]}" = "/home" ]
}

@test "add_overlay: deduplicates entries" {
    local -a overlay_dirs=()
    add_overlay "/home/user/project1"
    add_overlay "/home/user/project2"
    add_overlay "/tmp/stuff"
    [ "${#overlay_dirs[@]}" -eq 2 ]
    [ "${overlay_dirs[0]}" = "/home" ]
    [ "${overlay_dirs[1]}" = "/tmp" ]
}

@test "add_overlay: different top-level dirs all added" {
    local -a overlay_dirs=()
    add_overlay "/home/user"
    add_overlay "/var/lib"
    add_overlay "/opt/tool"
    [ "${#overlay_dirs[@]}" -eq 3 ]
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
