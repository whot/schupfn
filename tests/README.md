# Tests

Unit tests for schupfn, using [bats](https://github.com/bats-core/bats-core)
(Bash Automated Testing System).

## Dependencies

- [bats](https://github.com/bats-core/bats-core) >= 1.4
- [yq](https://github.com/mikefarah/yq) (for the `load_config` tests)

On Fedora:

    dnf install bats yq

## Running

From the repository root:

    bats tests/

Or run a single test file:

    bats tests/find_config.bats

## What's tested

| File                    | What it covers                                          |
|-------------------------|---------------------------------------------------------|
| `find_config.bats`      | Walking `$PWD` upward to find `.schupfn/config.yml`     |
| `load_config.bats`      | Parsing config YAML with yq, all fields and edge cases  |
| `classify_export.bats`  | Sorting export paths into dirs/files, symlink handling   |
| `session.bats`          | VM session tracking, join locks, stale session cleanup   |

Tests that need `yq` are skipped automatically if it's not installed.

## How it works

`test_helper.bash` sources the `schupfn` script without running `main()`
(there's a `BASH_SOURCE` guard at the bottom of the script). This gives
the tests direct access to all the internal functions.

The helper also overrides `die()` so it sets a flag instead of calling
`exit 1`. Tests that expect a failure use `|| true` to catch the return
code and then check `assert_die_called`.
