# Common setup for schupfn bats tests.
#
# Sources the schupfn script (without running main) and provides
# helper functions for test setup/teardown.

SCHUPFN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source schupfn to get access to all functions.
# The BASH_SOURCE guard at the bottom prevents main() from running.
source "$SCHUPFN_ROOT/schupfn"

# Override die() so tests can assert on failures without bats exiting.
# Sets _die_called=1 and _die_message to the error text, then returns 1.
die() {
    _die_called=1
    _die_message="$*"
    return 1
}

# Reset die tracking state. Call in setup().
reset_die() {
    _die_called=0
    _die_message=""
}

# Assert that die() was called with a message matching the given pattern.
assert_die_called() {
    local pattern="${1:-}"
    if [ "$_die_called" != "1" ]; then
        echo "expected die() to be called, but it wasn't" >&2
        return 1
    fi
    if [ -n "$pattern" ]; then
        if [[ "$_die_message" != *"$pattern"* ]]; then
            echo "die() message '$_die_message' does not contain '$pattern'" >&2
            return 1
        fi
    fi
}

# Assert that die() was NOT called.
assert_die_not_called() {
    if [ "$_die_called" = "1" ]; then
        echo "die() was called unexpectedly: $_die_message" >&2
        return 1
    fi
}

# Create a temp directory for the current test. Cleaned up automatically
# by bats via BATS_TEST_TMPDIR (bats >= 1.4) or manually.
make_tmpdir() {
    if [ -n "${BATS_TEST_TMPDIR:-}" ]; then
        echo "$BATS_TEST_TMPDIR"
    else
        local d
        d=$(mktemp -d)
        echo "$d"
    fi
}
