# install

The Subarchy installer ([ADR 0049](../docs/decisions/0049-installer.md)).
Omarchy counterpart: `/usr/share/omarchy/install/`, including
`omarchy-base.packages` (what the ISO pacstraps) and `omarchy-other.packages`
(optional and hardware packages). See
[package lists](../docs/inventory/generated/omarchy-packages.md).

## `subarchy-setup`

The guided installer on the live ISO (`cmd/subarchy-setup`). It asks for the
keyboard layout first and switches the console to it (`loadkeys`), so the
password and passphrase are typed under the layout the installed system
asks for them in. It then lists the disks of at least 20 GiB, leaving out
the install medium, and asks for the computer name, user name and password,
disk passphrase and time zone. The desktop layout and variant come from
systemd's `kbd-model-map`. Each answer is checked as it is entered. The user confirms
by typing the disk's name. It then writes the config and secret files (mode
600) under `/run/subarchy-setup` and runs `subarchy-install`. Subarchy's own
packages come from the repository on the image, `/opt/subarchy/repo`.

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

Not yet: the
Quickshell shell and themes, hardware detection, and a Limine entry that
chainloads another disk's bootloader.

A new system is on the stable channel: Arch packages come from the Arch
Linux Archive at the snapshot date the package ships; `subcult channel set
edge` follows the mirrors directly (ADR 0026).

With no network the install runs from the repository on the image alone,
which carries the whole install set (`make iso` downloads it); with network
the Arch mirrors come first and the image's copies serve as a cache. If the
install from the mirrors fails (an old image cannot verify packages signed
with newer keys), it is tried once more from the image alone.

The two Limine tools are AUR packages, and Pult is vendored from its
release PKGBUILD (`packaging/pult`), rebuilt locally into `build/repo` by

The two Limine tools are AUR packages, and the prebuilt Neovim is Subarchy's
own package (`packaging/subarchy-nvim`), rebuilt locally into `build/repo` by
`packaging/aur/build.sh` (needs docker) until the Subarchy repository
exists.

## Testing

`tools/iso/install-test.py ISO` (or `make install-test`) boots the live ISO
in QEMU with an empty disk. It shares this checkout over 9p and runs the
installer from it, so installer changes need no ISO rebuild. It then boots
the installed disk, types the LUKS passphrase on the serial console, logs in
and checks the result. Downloads are cached in `build/pkgcache`. With
`--guided` it instead answers `subarchy-setup` on the serial console, which
tests the setup command, installer and repository shipped on the image.
CI runs that form with the guest's network off after every ISO build
(`tools/ci/install-test.sh`).
