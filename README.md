# schupfn

Run [toolbox](https://containertoolbx.org/) containers inside ephemeral virtual
machines using [virtme-ng](https://github.com/arighi/virtme-ng).

The idea: you set up a toolbox container the way you like it, then
`schupfn enter` boots that container as a VM instead of entering it as a
container. Your current working directory is mounted read-write, everything
else on the host is inaccessible. This is useful when you want the
convenience of toolbox but need actual VM-level isolation -- for example,
to sandbox AI coding agents that might try to escape a container.

`schupfn enter` is meant to feel like `toolbox enter`, just with a VM
underneath.

["Schupfn"](https://en.wiktionary.org/wiki/Schupfn) is Austrian slang for a
shed. That's where you keep your toolboxes. The `u` is pronounced like the `u`
in "unsuccessful".

## Requirements

- [podman](https://podman.io/) and [toolbox](https://containertoolbx.org/)
- [virtme-ng](https://github.com/arighi/virtme-ng) (`vng`)
- [yq](https://github.com/mikefarah/yq) (only needed if you use a config file)

The toolbox container itself needs a few packages installed:
`openssh-server`, `systemd-udev`, and `busybox`. schupfn will notice if
they're missing and offer to install them for you.

You'll also need SSH public keys in `~/.ssh/id_*.pub` -- that's how
authentication into the VM works.

## Installation

Copy the script and man page to somewhere in your `$PATH`:

```sh
sudo install -m 755 schupfn /usr/local/bin/schupfn
sudo install -m 644 schupfn.1 /usr/local/share/man/man1/schupfn.1
```

## Quick start

```sh
# Create and set up a toolbox like you normally would
toolbox create mybox
toolbox run -c mybox sudo dnf install -y gcc make  # or whatever you need

# Enter it as a VM
schupfn enter mybox
```

That's it. schupfn exports the container filesystem, boots a VM with the
host kernel via virtme-ng, waits for SSH, and drops you into a shell.
Your `$PWD` is mounted at the same path inside the VM.

When you exit the shell, the VM shuts down.

## Exporting extra paths

By default only `$PWD` is available inside the VM. Use `--export-ro` and
`--export-rw` to add more:

```sh
# Mount a directory read-only into the VM
schupfn enter mybox --export-ro ~/src/other-project

# Mount a directory read-write
schupfn enter mybox --export-rw ~/src/work-in-progress

# Copy a file into the VM's home directory
schupfn enter mybox --export-ro ~/.zshrc
```

`--export-ro` mounts directories read-only at their original path.
`--export-rw` does the same but read-write. Files are copied into the VM
at their original absolute path (directory structure is preserved).
Symlinks are followed -- a symlink pointing to a directory is mounted,
one pointing to a file is copied.

Both flags are repeatable, pass them as many times as you like.

## Configuration files

schupfn supports multiple configuration files, in order of preference:
- `.schupfn/config.yml` for directory-local configuration. schupfn will walk
   up from `$PWD` and use the first one it finds.
- `$XDG_CONFIG_HOME/schupfn/<containername>-config.yml` for container-wide
  configuration. Use this when the same container is used across multiple
  projects. For example you may have a `gnome` toolbox for building the
  gnome stack and want to export the whole of gnome's source tree.
- `$XDG_CONFIG_HOME/schupfn/default-config.yml` as the fallback config
  if no other one is found. Use this as a fallback for paths you always need,
  e.g. shell setup.

The supported keys in the configuration file are:

```yaml
container: my-toolbox
command: make test

export-ro:
  - ~/src/shared-lib
  - ~/.zshrc
export-rw:
  - ~/src/work-in-progress

vm:
  memory: 8G
  cpus: 4
  network: false

ssh_key: ~/.ssh/id_ed25519
```

All fields are optional. CLI arguments override config values -- if you
pass `--memory 2G` on the command line, that wins over whatever the config
says. For `--export-ro` and `--export-rw`, both lists are merged (config
entries first, then CLI entries).

Parsing requires [yq](https://github.com/mikefarah/yq).

### Config reference

| Key          | Type          | Description                                        |
|--------------|---------------|----------------------------------------------------|
| `container`  | string        | Default container name if none given on the CLI    |
| `command`    | string        | Command to run instead of an interactive shell     |
| `export-ro`  | list of paths | Read-only exports, same as `--export-ro`           |
| `export-rw`  | list of paths | Read-write exports, same as `--export-rw`          |
| `vm.memory`  | string        | VM memory, e.g. `4G`, `512M` (default: `4G`)       |
| `vm.cpus`    | int           | VM CPU count (default: host CPU count)              |
| `vm.network` | bool          | Set to `false` to disable the extra network device  |
| `ssh_key`    | path          | SSH private key to use for the VM connection        |

## Commands

### `schupfn enter [<name>] [options]`

Export the container and boot it as a VM.

| Option               | Description                                              |
|----------------------|----------------------------------------------------------|
| `--export-ro <path>` | Mount a directory read-only or copy a file (repeatable)  |
| `--export-rw <path>` | Like `--export-ro`, but directories are mounted read-write|
| `--command <cmd>`    | Run a command in the VM instead of an interactive shell   |
| `--config <path>`    | Use a specific config file instead of searching for one   |
| `--refresh`          | Force re-export of the rootfs                             |
| `--deep-check`       | Use `podman diff` for thorough staleness detection        |
| `--memory <size>`    | VM memory (default: `4G`)                                 |
| `--cpus <n>`         | VM CPU count                                              |
| `--no-network`       | Disable the extra network device (SSH still works)        |
| `--verbose`          | Show VM boot output                                       |

### `schupfn join [<name>] [options]`

Open a new SSH session to an already-running VM. This allows multiple
terminal sessions to share the same VM without starting a second one.

If `<name>` is omitted and exactly one VM is running, that VM is joined
automatically. If multiple VMs are running, an interactive menu is shown.

```sh
# In terminal 1:
schupfn enter mybox

# In terminal 2 -- join the same VM:
schupfn join mybox

# If only one VM is running, the name can be omitted:
schupfn join

# Run a command in a running VM:
schupfn join mybox --command "make test"
```

| Option            | Description                                             |
|-------------------|---------------------------------------------------------|
| `--command <cmd>` | Run a command in the VM instead of an interactive shell  |

### `schupfn list`

Show cached rootfs entries with their freshness status and size.

### `schupfn clean [<name>]`

Remove cached rootfs entries. Without a name, removes all of them (with
confirmation).

## How it works

1. The container's filesystem is exported via `podman export` into
   `$XDG_CACHE_HOME/schupfn/roots/<name>/`. This is cached and only
   re-exported when the container changes (image ID, container ID, or
   `podman inspect` output differ).

2. The rootfs is patched: your user is added to `/etc/passwd` if needed,
   virtio kernel modules are copied in for networking, and sshd's
   privilege separation directory gets a workaround for 9p ownership
   issues.

3. virtme-ng boots a VM using the host kernel with the exported rootfs.
   `$PWD` and any exported directories are mounted via 9p at their
   original paths.

4. schupfn waits for sshd inside the VM to come up, copies any exported
   files into the VM at their original paths, then opens an interactive
   SSH session.

5. When you exit, the VM is killed and cleaned up.

## Cache

Exported rootfs trees live under `~/.cache/schupfn/roots/` (or
`$XDG_CACHE_HOME/schupfn/roots/`). They're reused across runs until the
container changes. Use `schupfn clean` to reclaim disk space.

## License

Apache-2.0
