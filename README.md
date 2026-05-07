# schupfn

Run [toolbox](https://containertoolbx.org/) containers inside ephemeral virtual
machines using [qemu](https://www.qemu.org/).

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
- [qemu](https://www.qemu.org/) (`qemu-system-x86_64`, `qemu-img`)
- [libguestfs-tools](https://libguestfs.org/) (`virt-make-fs`, `virt-customize`)
- [yq](https://github.com/mikefarah/yq) (only needed if you use a config file)

The packages `openssh-server`, `systemd-udev`, and `dbus-broker` are
required inside the VM and are installed automatically during
`schupfn create`.

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

That's it. schupfn exports the container to a qcow2 disk image, boots a
VM with the host kernel via qemu, waits for SSH, and drops you into a
shell. Your `$PWD` is mounted at the same path inside the VM.

When you exit the shell, the VM shuts down.

## Exporting extra paths

By default only `$PWD` is available inside the VM. Use `--export-ro` and
`--export-rw` to add more:

```sh
# Mount a directory read-only into the VM
schupfn enter mybox --export-ro ~/src/other-project

# Mount a directory read-write
schupfn enter mybox --export-rw ~/src/work-in-progress

# Mount a directory as copy-on-write (writable in VM, host unchanged)
schupfn enter mybox --export-cow ~/src/reference-tree

# Copy a file into the VM's home directory
schupfn enter mybox --export-ro ~/.zshrc
```

`--export-ro` mounts directories read-only at their original path.
`--export-rw` does the same but read-write.
`--export-cow` mounts directories read-only from the host but writable
inside the VM via overlayfs -- writes go to a tmpfs upper layer and are
lost when the VM shuts down. The host directory is never modified.
Files are copied into the VM at their original absolute path (directory
structure is preserved). Symlinks are followed -- a symlink pointing to
a directory is mounted, one pointing to a file is copied.

All flags are repeatable, pass them as many times as you like.

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
| `export-cow` | list of paths | Copy-on-write exports, same as `--export-cow`      |
| `follow-git-worktrees` | bool | Auto-export main git dir for worktrees              |
| `image-size` | string        | Disk image size, e.g. `4G`, `10G` (default: auto)    |
| `vm.memory`  | string        | VM memory, e.g. `4G`, `512M` (default: `4G`)       |
| `vm.cpus`    | int           | VM CPU count (default: host CPU count)              |
| `vm.network` | bool          | Set to `false` to disable the extra network device  |
| `vm.display` | string        | Display adapter: `virtio`, `qxl`, `std` (default: none) |

## Commands

### `schupfn enter [<name>] [options]`

Export the container and boot it as a VM.

| Option               | Description                                              |
|----------------------|----------------------------------------------------------|
| `--export-ro <path>` | Mount a directory read-only or copy a file (repeatable)  |
| `--export-rw <path>` | Like `--export-ro`, but directories are mounted read-write|
| `--export-cow <path>`| Writable in VM via overlayfs, host directory unchanged    |
| `--command <cmd>`    | Run a command in the VM instead of an interactive shell   |
| `--config <path>`    | Use a specific config file instead of searching for one   |
| `--refresh`          | Force re-export of the disk image                         |
| `--deep-check`       | Use `podman diff` for thorough staleness detection        |
| `--memory <size>`    | VM memory (default: `4G`)                                 |
| `--cpus <n>`         | VM CPU count                                              |
| `--no-network`       | Disable the extra network device (SSH still works)        |
| `--image-size <size>`| Disk image size, e.g. `4G` (default: auto)              |
| `--follow-git-worktrees` | Auto-export main git dir when in a worktree          |
| `--display <type>`   | Add a display adapter (`virtio`, `qxl`, `std`)            |
| `--console`          | Boot with serial console instead of SSH (for debugging)   |
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

Show cached VM images with their freshness status and size.

### `schupfn clean [<name>]`

Remove cached VM images. Without a name, removes all of them (with
confirmation).

## How it works

1. The container's filesystem is exported via `podman export` to a
   tarball, then converted to a qcow2 disk image using `virt-make-fs`.
   The image is cached under `$XDG_CACHE_HOME/schupfn/images/<name>/`
   and only re-exported when the container changes.

2. The image is customized via `virt-customize`: your user is added,
   SSH host keys are generated, sshd is enabled, a systemd service
   for mounting 9p shares is installed, and networking is configured.

3. qemu boots a VM using the host kernel and initramfs with the qcow2
   image as the root filesystem. Each session gets a copy-on-write
   snapshot so the base image stays clean.

4. `$PWD` and any exported directories are mounted via 9p at their
   original paths. schupfn waits for sshd to come up, copies any
   exported files, then opens an interactive SSH session.

5. When you exit, the VM is killed and cleaned up. The snapshot is
   deleted but the base image is preserved for next time.

## Cache

Cached VM images live under `~/.cache/schupfn/images/` (or
`$XDG_CACHE_HOME/schupfn/images/`). They're reused across runs until the
container changes. Use `schupfn clean` to reclaim disk space.

## License

Apache-2.0
