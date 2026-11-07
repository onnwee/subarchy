---
title: "First install on sputnik"
type: review
status: draft
review: pending
created: 2026-11-07
updated: 2026-11-07
tags: [review, installer]
aliases: [First install, Install runbook]
---

# First install on sputnik

How to put the current Subarchy on `sputnik`'s empty second drive
([[0049-installer|ADR 0049]]), and what has and has not been tested. Written
2026-11-07 after the overnight build-out; everything below "Tested" passed
in the QEMU install test on `sputnik` (`make install-test`, 44 checks).

## What you get

A bare system, not yet a daily driver: LUKS2 and btrfs with snapshots, both
kernels, Limine with snapshot entries, SDDM, and a Hyprland session with
Subarchy's defaults. There is **no shell yet** (no bar, launcher or
notifications), and the only app is kitty (Super+Enter). Apps come from
`subcult app install`, for example `subcult app install zen obsidian`.

## Tested in the VM

- Install with `subarchy-setup`, LUKS unlock at boot, login.
- btrfs subvolumes, zstd, zram, snapper, the `@factory` snapshot.
- Limine snapshot entries; booting a snapshot; restoring it and booting the
  result.
- `subcult update` with no password prompt, the daily update check.
- SDDM greeter on screen and a uwsm/Hyprland session with the defaults.
- ufw, AppArmor, DNS-over-TLS, sysctl hardening, Avahi, power profiles.
- Hardware detection in a VM (no firmware), the GPU hook staying silent.
- `subcult secureboot setup` on Secure Boot firmware, then booting with it
  enforced, twice.

## Not tested on real hardware

- **NVIDIA**: `nvidia-open-dkms` building for both kernels, GPU modes,
  `subcult gpu run`. On sputnik, `subcult hw packages` picks the same
  drivers sputnik uses now.
- Intel Wi-Fi through NetworkManager, SOF audio, Bluetooth, suspend, lid,
  battery profile switching.
- The graphical Plymouth splash (the VM test runs Plymouth in text mode).
- DisplayLink: `evdi`/`displaylink` are not installed by anything yet.
- Secure Boot on the real firmware.

## Steps

1. Build the image on sputnik: `make iso` (about 15 minutes, asks for sudo),
   then `make iso-test`. The image is `build/iso/subarchy-<date>-x86_64.iso`.
2. Write it to a USB stick. Check the stick's device name with `lsblk`
   first; `dd` overwrites whatever it is given:
   `sudo dd if=build/iso/subarchy-*.iso of=/dev/sdX bs=4M oflag=direct status=progress`.
3. Turn Secure Boot off if it is on (the image is unsigned) and boot the
   stick from the firmware's boot menu.
4. Get online: Ethernet works as is; for Wi-Fi run `iwctl`, then
   `station wlan0 connect <network>`. Arch packages download during install.
5. Run `subarchy-setup`. Pick the **SPCC M.2 PCIe SSD** (`nvme0n1`,
   1.0 TB), not the **CT1000P5PSSD8** (`nvme1n1`, Omarchy). Device names can
   change between boots; go by the model. The other disk is not touched.
6. Reboot. The installer adds a firmware entry named **Limine** and puts it
   **first** in the boot order, so Subarchy becomes the default. Omarchy's
   entry stays; choose it from the firmware boot menu, or move it back
   first with `efibootmgr --bootorder`.
7. After the first login: `subcult hw info`, `subcult app list`,
   `subcult update`. Optional: `sudo subcult secureboot setup` with the
   firmware in setup mode.

Related: [[0049-installer|ADR 0049]] · [[roadmap|Roadmap]] · [[review-index|Review index]]
