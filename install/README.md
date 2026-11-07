# install

The Subarchy installer ([ADR 0049](../docs/decisions/0049-installer.md)).
Omarchy counterpart: `/usr/share/omarchy/install/`, including
`omarchy-base.packages` (what the ISO pacstraps) and `omarchy-other.packages`
(optional and hardware packages). See
[package lists](../docs/inventory/generated/omarchy-packages.md).

## `subarchy-install`

The scripted stage. It runs as root on the live ISO, reads a `KEY=value`
config file (keys listed in the script's header) and needs `--yes`, because
it wipes the disk named by `DISK`. It refuses a disk that has mounted
partitions or that holds the install medium. Other disks are left alone.

What it builds:

| Step | Result | ADR |
|---|---|---|
| Partition | GPT: 4 GiB FAT32 ESP at `/boot`, rest LUKS2 | 0009, 0010 |
| Filesystems | btrfs `@ @home @log @pkg`, `compress=zstd:3,noatime` | 0009 |
| Packages | `packages/base.txt` via pacstrap | 0002, 0004 |
| initramfs | systemd hooks with `sd-encrypt`; `limine-mkinitcpio-hook` builds one UKI per kernel in `/boot/EFI/Linux` | 0008 |
| Boot | Limine with its own firmware entry and the `EFI/BOOT` fallback; menu from `/etc/default/limine` | 0007 |
| Snapshots | snapper config `root` for `@`, 5 numbered, no timeline; `limine-snapper-sync` adds a boot entry per snapshot | 0011 |
| System | zram swap, NetworkManager, timesyncd, user in `wheel` with zsh, root locked | 0014, 0016 |
| Services | ufw (incoming denied), AppArmor, systemd-resolved with Quad9 DoT, Avahi, power-profiles-daemon, thermald on Intel, BlueZ, Plymouth | 0013, 0018-0021, 0063 |
| Desktop | `packages/desktop.txt`: SDDM, Hyprland under uwsm, portals, PipeWire, kitty, fonts; the user's `~/.config/hypr/hyprland.lua` | 0017, 0029-0033, 0040 |
| Factory reset | read-only `@factory` snapshot of the fresh `@` | 0049, 0056 |

Not yet: the TUI that asks the questions and writes the config, the
Quickshell shell and themes, hardware detection, a Limine entry that chainloads
another disk's bootloader, and the offline package cache.

The two Limine tools are AUR packages rebuilt locally into `build/repo` by
`packaging/aur/build.sh` (needs docker) until the Subarchy repository
exists.

## Testing

`tools/iso/install-test.py ISO` (or `make install-test`) boots the live ISO
in QEMU with an empty disk. It shares this checkout over 9p and runs the
installer from it, so installer changes need no ISO rebuild. It then boots
the installed disk, types the LUKS passphrase on the serial console, logs in
and checks the result. Downloads are cached in `build/pkgcache`.
