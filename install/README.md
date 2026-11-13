# install

The Subarchy installer ([ADR 0049](../docs/decisions/0049-installer.md)).
Omarchy counterpart: `/usr/share/omarchy/install/`, including
`omarchy-base.packages` (what the ISO pacstraps) and `omarchy-other.packages`
(optional and hardware packages). See
[package lists](../docs/inventory/generated/omarchy-packages.md).

## `subarchy-setup`

The guided installer on the live ISO (`cmd/subarchy-setup`). It starts by
itself on the first console; on a serial console or over SSH, run
`subarchy-setup`.

On a virtual console it is full-screen (`screens.go`; the flow follows
Omarchy's installer): a greeter, then one cleared screen per question
under the SUBCULT mark, with `gum` drawing the lists and inputs. The
language screen sets the installed system's locale (the installer stays
in English) and preselects that language's usual keyboard. The
keyboard comes from a labelled list, the time zone from a searchable
list, and the disk from a list that shows what is on each one, internal
disks before USB and removable ones. The time zone list opens on a
guess: online, the zone of the network's location, from whichever of
ipapi.co and ipwho.is answers first within 4 seconds (the request sends
them the network's public address); otherwise the zone of the chosen
language's country, or UTC for a language spoken across several, such
as English (US). The page says where the guess came from. After
choosing a disk the user can install there, browse it read-only first, or
pick another. Before the browse opens, a page lists the partitions it
mounted read-only and the ones it left closed (encrypted, LVM, RAID, ZFS,
swap, no filesystem, or a failed mount) and says how to come back: q, or
Esc then 0, or F10. A summary table of every answer, the disk included, then
asks "Does this look right?", and the erase question comes last; its
default is no. Escape goes back a step on every screen. While `subarchy-install` runs, the screen shows
the mark in the middle of the screen, "Installing Subarchy" with the time
so far at the right, a bar with a percentage, the current phase and a
rotating tip (`progress.go`). L switches a window with the end of the
install log on and off; the raw output goes to `/var/log/subarchy-install.log`,
which is also where the percentage is read from. The finish screen offers
"Reboot now". A failure says why the install stopped (subarchy-install's
own fatal message, the line that starts `subarchy-install: error:`, else
the last pacman or mkinitcpio error; its warnings, such as a failed
`pult apply`, never count) and at which step,
shows the end of this run's log and offers a menu. `--plain`
gives the prompts below instead.

After the keyboard comes a network page, but only when no link has a
default route and iwd has a Wi-Fi device in station mode (`network.go`). A
wired machine, or one with no Wi-Fi card, goes straight on. The page
lists the networks iwd sees, strongest first, with "Look for networks
again" and "Skip, install offline" below them. For a password network it
asks the passphrase as a hidden input, joins with `iwctl`, and waits up to
20 seconds for an address. The passphrase has 8 to 63 characters; the
64-digit key is refused there, because iwd joins only with the passphrase.
802.1X and WEP networks are listed, but the installer will not join them.
A network whose name holds control characters is not listed, since any
access point nearby picks its name and could otherwise send escape
sequences to the console. Names are passed to gum and `iwctl` after `--`,
so one starting with `-` is not read as an option. iwd's state is read
over D-Bus (`busctl --json=short`), not from `iwctl`'s table. Skipping is
safe: the install runs from the image's repository.

Whatever Wi-Fi network the live session is on when the questions end,
joined on this page or by hand with `iwctl` before the installer started,
goes to the installed system. The summary lists it. The passphrase is the
one typed on the page, or else what iwd saved in `/var/lib/iwd`, with
iwd's escapes (`\s`, `\\` and the rest) undone. It goes
to `subarchy-install` like the other secrets: `WIFI_SSID` in the config
and the passphrase in a mode-600 file named by `WIFI_PSK_FILE`. The
installer writes
`/etc/NetworkManager/system-connections/<name>.nmconnection` (mode 600),
so the first boot is online. Neither the passphrase nor `iwctl`'s output
reaches the screen or the install log. A wired link needs nothing carried
over: NetworkManager starts DHCP on it by itself.

The console font follows the screen: before every screen the installer
reads the framebuffer's width (`/sys/class/graphics/fb0/virtual_size`) and
sets the largest Terminus font that still leaves 100 columns, which is
the 32-pixel one from 1600 pixels up. It uses the code page 437 set
(`ter-i32b`): that one has the half blocks and shades the mark is drawn
with.

On a serial console or over SSH it asks plain line prompts. It asks for the
keyboard layout first and switches the console to it (`loadkeys`), so the
password and passphrase are typed under the layout the installed system
asks for them in. With no link up and a Wi-Fi device it then lists the
Wi-Fi networks by number, as on the network page; `s` skips and `r` looks
again. It then lists the disks of at least 20 GiB with the
partitions already on each, leaving out the install medium. Answering
`look 1` mounts that disk's plain filesystems read-only and `noexec`
under `/run/subarchy-look`, prints the same list of what it opened and
what it left closed, and asks before opening `mc` there. `mc` gets both
panels on `/run/subarchy-look`, no subshell (`--nosubshell`) and a
temporary profile (`MC_PROFILE_ROOT`) with the command line hidden, q
bound to quit, Ctrl-O and F2 unbound, a confirmation before running a
file, an empty user menu and the nicedark skin, whose text stays readable
in the installer palette. Typed letters search the panel, and Return on a
file does not run it. `mc`'s pull-down menus can still run a command
typed into one of their dialogs, as root. It then asks for the computer name, user name and password
and time zone; online, the time zone's default is the network's zone,
found as on the screens. The disk passphrase is the user's password unless the user
asks for a separate one. The desktop layout and variant come from
systemd's `kbd-model-map`. Each answer is checked as it is entered. The user confirms
with a yes/no question whose default is no. It then writes the config and
secret files (mode 600) under `/run/subarchy-setup` and runs
`subarchy-install`. When that finishes it says how long the install took
and offers to reboot; when it fails it shows the end of the log and a menu
(view the log, shell, reboot, power off). `--batch` leaves out the browse,
the reboot offer and the menu, for the VM test. Subarchy's own
packages come from the repository on the image, `/opt/subarchy/repo`.

## `subarchy-install`

The scripted stage. It runs as root on the live ISO, reads a `KEY=value`
config file (keys listed in the script's header) and needs `--yes`, because
it wipes the disk named by `DISK`. It refuses a disk that has mounted
partitions or that holds the install medium, and a user name that is
already an account or group on the live image, or one of the groups the
installed system adds (`docker`, `realtime`), which `useradd` would refuse
after the wipe. Other disks are left alone.

What it builds:

| Step | Result | ADR |
|---|---|---|
| Partition | GPT: 4 GiB FAT32 ESP at `/boot`, rest LUKS2 | 0009, 0010 |
| Filesystems | btrfs `@ @home @log @pkg`, `compress=zstd:3,noatime` | 0009 |
| Packages | `packages/base.txt` via pacstrap | 0002, 0004 |
| initramfs | systemd hooks with `sd-encrypt`; `limine-mkinitcpio-hook` builds one UKI per kernel in `/boot/EFI/Linux`, once, during pacstrap (pacstrap runs the target's pacman hooks); `rd.luks.options=discard,tries=0`, so a wrong disk passphrase asks again instead of ending in the emergency shell | 0008 |
| Boot | Limine with its own firmware entry and the `EFI/BOOT` fallback; menu from `/etc/default/limine` | 0007 |
| Snapshots | snapper config `root` for `@`, 5 numbered, no timeline; `limine-snapper-sync` adds a boot entry per snapshot | 0011 |
| System | zram swap, NetworkManager, timesyncd, user in `wheel` with zsh, root locked | 0014, 0016 |
| Hardware | `subcult-hw` picks firmware, microcode, GPU drivers, services and fixes; the wireless regulatory domain from the time zone, applied by `wireless-regdb` | 0005, 0006, 0050 |
| Wi-Fi | with `WIFI_SSID` set, a NetworkManager connection for that network, mode 600, with the passphrase from `WIFI_PSK_FILE` (none for an open network); a name that is not plain letters, digits, `_ . -` and inner spaces is written as its bytes; the file name never starts with a dot, which NetworkManager would skip; `key-mgmt=wpa-psk`, which NetworkManager also uses for WPA3 (SAE) when the Wi-Fi card supports it | 0016 |
| Containers | Docker with compose and buildx; `docker.socket` enabled so the daemon starts on demand; the user is not in the `docker` group (`sudo subcult docker sudoless` grants it behind a warning), and lazydocker (`subcult docker tui`, the launcher's lazydocker entry) reaches the daemon through a polkit prompt; `ufw-docker` rules added at first boot by `subcult-ufw-docker.service` | 0055, 0019 |
| Tailscale | `tailscale` installed, `tailscaled` enabled; nobody is signed in until the user signs in from the bar's Tailscale panel (or `sudo tailscale up`). No account is tailscaled's operator: the panel goes through a root helper under the polkit action `tv.subcult.tailscale`. The installer enables `subcult-taildrop@<user>.service`, which saves files sent with Taildrop to the user's `~/Downloads` | 0058, 0062 |
| Shell setup | the user's `~/.zshrc` and `~/.bashrc` source `/usr/share/subcult/default/shell/zshrc` and `bashrc`: aliases, functions, starship with Subarchy's prompt, atuin (Ctrl-R), zoxide, fzf keys, mise | 0041 |
| Services | ufw (incoming denied; LocalSend's 53317 tcp and udp open), AppArmor, systemd-resolved with Quad9 DoT, Avahi, power-profiles-daemon, thermald on Intel, BlueZ, Plymouth | 0013, 0018-0021, 0063 |
| Command-line tools | `packages/cli.txt`: the app list's command-line and terminal apps (shell tools, starship, atuin, btop, yazi, lazygit, tmux, forge clients, media tools, Codex and OpenCode) | 0041, 0044 |
| Desktop | `packages/desktop.txt`: SDDM, Hyprland under uwsm, portals, PipeWire, kitty, fonts; the user's `~/.config/hypr/hyprland.lua` | 0017, 0029-0033, 0040 |
| Boot entries | firmware entries named Limine or Subarchy whose partition no longer exists (left by an earlier install on a disk since wiped) are removed; other systems' entries are not touched | 0007 |
| Factory reset | read-only `@factory` snapshot of the fresh `@` | 0049, 0056 |

Not yet: a Limine entry that chainloads another disk's bootloader.

A new system is on the stable channel: Arch packages come from the Arch
Linux Archive at the snapshot date the package ships; `subcult channel set
edge` follows the mirrors directly (ADR 0026).

With no network the install runs from the repository on the image alone,
which carries the whole install set (`make iso` downloads it); with network
the Arch mirrors come first and the image's copies serve as a cache. If the
install from the mirrors fails (an old image cannot verify packages signed
with newer keys), it is tried once more from the image alone.

The two Limine tools are AUR packages, and the prebuilt Neovim is Subarchy's
own package (`packaging/subarchy-nvim`), rebuilt locally into `build/repo` by
`packaging/aur/build.sh` (needs docker) until the Subarchy repository
exists.
Pult is vendored from its release PKGBUILD (`packaging/pult`) and builds
the same way.

## Testing

`tools/iso/install-test.py ISO` (or `make install-test`) boots the live ISO
in QEMU with an empty disk. It shares this checkout over 9p and runs the
installer from it, so installer changes need no ISO rebuild. It then boots
the installed disk, types three wrong LUKS passphrases and then the right
one on the serial console (the prompt must keep asking), logs in and checks
the result. Downloads are cached in `build/pkgcache`. With
`--guided` it instead answers `subarchy-setup`'s full screens on a virtual console (keys through QMP, text read back from `/dev/vcs`), which
tests the setup command, installer and repository shipped on the image.
CI runs that form with the guest's network off after every ISO build
(`tools/ci/install-test.sh`). The VM has no Wi-Fi, so the test checks
only that the keyboard is followed by the time zone, without the network
page. The Go tests drive that page against a fake iwd, and
`tools/test/installer-check-test.sh` checks the connection file.
