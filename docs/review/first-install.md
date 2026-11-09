---
title: "First install on sputnik"
type: review
status: draft
review: pending
created: 2026-11-07
updated: 2026-11-08
tags: [review, installer]
aliases: [First install, Install runbook]
---

# First install on sputnik

Issue [#75](https://git.subcult.tv/subculture-collective/subarchy/issues/75)
owns the second-drive install and its hardware results. Kvant coordinates
the installation so this session survives Sputnik reboots. The owner will
perform the remaining physical acceptance tests. Keep the issue open until
those results are recorded; a VM pass does not satisfy them.

## Current desktop and evidence

Installer source `144cdf27ff561b18d6187606fecbc61406d5910c` (PR #207),
checked on 2026-11-08, includes the Quickshell bar, launcher, notifications, widgets,
standalone lock, themed screensaver, SDDM greeter and Hyprland session. The
installer supplies kitty, Neovim with the packaged configuration, the shell
and desktop dependencies. Additional applications come through
`subcult app install`; the app catalog is not an installation receipt.

The base system includes LUKS2, btrfs subvolumes and snapshots, linux-zen
and linux-lts, Limine, zram, NetworkManager, PipeWire, Bluetooth, AppArmor
and ufw. Hardware detection selects firmware and GPU packages. DisplayLink
detection now selects `evdi-dkms` and `displaylink` and enables the service
([[0050-hardware-support|ADR 0050]]). No DisplayLink adapter was attached
during the November 8 preflight; test it with the dock attached.

The source-thread receipt on Sputnik,
`/home/onnwee/.t3/worktrees/Subarchy/t3-960119c8/build/vm-fixture-install3.log`,
records 77 passing fresh VM checks (exit 0), as handed over by that thread.
It covers the default shell/greeter, lock and battery behavior, theme
idempotence, budgets, snapshots, Secure Boot and TPM with emulated hardware.
That run combined a rebuilt package with an older live ISO. It does not
qualify that ISO as a current offline installation artifact.

Main advanced to `e717f0e8a14f8dec6287b9885757954f48ae5413` (#208) during
the new image build. Its changes are confined to CI and documentation;
the installer, package recipes and runtime sources match the pinned build.

The parent thread is fixing the missing signed `[subarchy]` repository
section for installed systems under #67. After that change merges, install
its updated core package and rerun `subcult channel set stable` before
checking online updates. Record that package revision separately from this
ISO; offline installation does not depend on the published repository.

## Live disk identification

Observed directly on **Sputnik, 2026-11-08** from Kvant over SSH:

| Role | Model | Serial | Capacity | Device at observation |
|---|---|---|---|---|
| Proposed Subarchy target | SPCC M.2 PCIe SSD | `AA231221NV01KG05237` | 1,000,204,886,016 bytes | `/dev/nvme0n1` |
| Existing Omarchy, retain | CT1000P5PSSD8 | `222839D04356` | 1,000,204,886,016 bytes | `/dev/nvme1n1` |
| Proposed installer USB | USB DISK 3.0 | `07002AC6C31EA238` | 62,025,367,552 bytes | `/dev/sda` |

The SPCC has an empty GPT and no partitions or mounted filesystems in
`lsblk`; `wipefs --no-act` reports GPT/PMBR signatures. This observation
does not authorize erasure or prove old data cannot be recovered. The USB
holds a Debian 13.7 installer and one automounted partition. Writing the
new image will replace that installer.

Omarchy's live root is `/dev/mapper/root`, backed by the Crucial's LUKS2
partition 2; its FAT32 partition 1 is mounted at `/boot`. The root btrfs
UUID is `4f537c0d-73ef-49cf-900e-9bb790d89001`; its LUKS UUID is
`9ed35003-158c-46d6-bb75-d896f4ed5c04`. Firmware entry `0002` is the current
Omarchy Limine entry on that disk. The observed boot order is
`0002,0000,0001`. Secure Boot's EFI variable reads disabled.

**Recheck these facts in the live environment immediately before erasing.**
Use model, serial, byte size, by-id path and mounted-device ancestry;
NVMe numbering and firmware entry numbers can change. Intended stable
paths at preflight:

```text
/dev/disk/by-id/nvme-SPCC_M.2_PCIe_SSD_AA231221NV01KG05237
/dev/disk/by-id/nvme-CT1000P5PSSD8_222839D04356
/dev/disk/by-id/usb-_USB_DISK_3.0_07002AC6C31EA238-0:0
```

## Recovery and access before reboot

Private receipts live at `~/.local/state/subarchy-install-75/` on Sputnik
and `~/.local/state/subarchy-install-75/recovery/` on Kvant. The latter has
matching SHA-256 copies of Omarchy's ESP archive and LUKS header, along
with partition maps, disk evidence, ESP file hashes and firmware entry/order
evidence. All 15 archived ESP files also match the live preflight file hashes. These are boot-recovery copies,
not a backup of all Omarchy user data. Do not publish the archive,
encrypted-volume header or network credentials.

Keep Omarchy's ESP, encrypted partition and boot entries intact. Subarchy
gets its own 4 GiB ESP on the SPCC. After installer hooks run, inspect the
new firmware entry's partition GUID and loader path, give it a distinct
Subarchy label, and restore Omarchy's previous default order. Use
`BootNext` for the first Subarchy boot. Re-read actual entry numbers before
any `efibootmgr` write. Do not enable Secure Boot, replace firmware keys or
enroll TPM unlock as part of the initial install.

Kvant's SSH alias currently reaches Omarchy over Sputnik's Wi-Fi and
trusts Omarchy's host key. The live image and installed Subarchy must have
separate host-key identities and dedicated known-hosts entries. Do not
disable host-key checks or replace Omarchy's trusted entry.

A private ISO overlay supplies a dedicated Kvant public login key, a
live-medium SSH host key and key-only root SSH configuration. It contains
no owner's login password, LUKS passphrase or Wi-Fi credentials. Keep this
personalized image private. Verify its SSH identity and key login in a VM
before booting hardware.

The owner may need to select the USB in the firmware menu and connect
Wi-Fi at the live console using `iwctl` (run `device list` first; interface
names can change). Wired networking can avoid this Wi-Fi step. Verify
trusted SSH from Kvant to the live environment before starting setup.
Notify the parent thread before rebooting Sputnik and confirm its work
has durable state.

## Installation sequence

1. Build from pinned current `origin/main` in an independent checkout;
   check space first. Reused caches do not establish freshness. Use a
   unique `SUBARCHY_ISO_WORK` so another build's work is not removed.
   Record the source revision, private access overlay, ISO hash and
   package manifest. Keep build-only Python dependencies isolated.
2. Run `make iso-test`, then `make install-test-offline` against that exact
   ISO. The latter drives the image's own setup with the guest network
   disabled. Record full results rather than substituting the earlier
   fixture receipt.
3. Present the USB's live model, serial, capacity and contents to the owner
   and obtain the destructive checkpoint before writing. Unmount its
   partitions, write only the approved whole-disk by-id path, flush writes
   and compare the ISO bytes read back from the device.
4. Boot the USB, establish trusted SSH and re-identify both SSDs. Check
   that the SPCC has no mounts, swap or active mappings and that the
   Crucial is not used as the target or ESP. Present the exact SPCC target
   and partition/encryption plan for the owner's destructive checkpoint.
5. Obtain the real account password and LUKS passphrase through T3's
   `request_secret`, one secret per card. Use owner-only temporary files
   in live RAM; never reuse VM credentials or print secrets. Use hostname
   `sputnik`, user `onnwee`, America/Chicago, US keyboard and en_US.UTF-8
   unless the owner requests otherwise.
6. Install through `subarchy-setup` or its scripted `subarchy-install`
   stage with the approved by-id target. Prefer the image's offline
   repository to tie the installed set to the tested artifact. Keep the
   Crucial unopened and unmounted. Capture installer/package and hardware
   selection results without credentials.
7. Before booting the new OS, mount only the SPCC for access provisioning.
   Install OpenSSH from the image's repository, add the dedicated Kvant
   public key for `onnwee`, enable `sshd`, and allow SSH through ufw only
   from Kvant's verified LAN address. Copy only the needed Wi-Fi profile
   through protected private storage; do not migrate Omarchy's home, T3
   state or VPN identity. Generate new SSH host keys and pin their public
   identity on Kvant. Check permissions, services and firewall rules.
8. Inspect firmware entries and the new ESP; mount Omarchy's ESP read-only
   only for the post-install hash comparison. Restore the Omarchy default,
   then set the one-time Subarchy boot. The owner must type the passphrase
   locally at first boot; SSH starts after disk unlock. Verify trusted
   SSH, new root/ESP ancestry on the SPCC, installed revision evidence,
   kernels, failed units and login session. Compare Omarchy's ESP hashes
   and partition map with preflight.
9. Arrange an Omarchy boot through the firmware menu and verify its actual
   root and SSH identity before marking recovery boot passed. Return to
   Subarchy for owner testing. Delete temporary password files after use;
   keep private recovery receipts on Kvant.

## Installation results

Artifact prepared on Sputnik, 2026-11-08:

- ISO: `~/.cache/subarchy-install-75/source/build/iso/subarchy-2026.11.08-x86_64.iso`,
  4,346,556,416 bytes. Independent Kvant copy:
  `~/.local/state/subarchy-install-75/subarchy-2026.11.08-x86_64.iso`.
- Both ISO copies: SHA-256
  `84de29b725a4e311ca13817cccacf1fa197729c3e9bbd4fb25d3e1d5fcee8c31`.
- Rebuilt core package: SHA-256
  `f69eba323240ae3b6e4bec4ced369fac6849f07969bb91faedd1204a0bd0396c`.
  A manifest records all 635 repository package files. Reused non-core
  recipes are unchanged from cache source `35b3058`; the core was rebuilt.
- Live boot: **PASS**, five checks, kernel `7.2.14-zen1-1-zen`, system
  `running`. Trusted Kvant-to-live-VM key login: **PASS**, with password
  and keyboard-interactive authentication disabled.
- Guided offline installer: **PASS**, completed in 262 seconds with the
  guest network disabled. The complete run passed **78 checks, 0 failed,
  exit 0**, including snapshots and emulated Secure Boot/TPM. Subsequent
  installed-system checks enable VM networking; they do not qualify
  physical hardware. High-level receipts are copied to Kvant's private
  state directory as `boot-test.log`, `offline-install-test.log` and
  `kvant-live-ssh-test.log`.
- Real Sputnik recheck at 23:02 CST: all 15 Omarchy ESP file hashes still
  match preflight; firmware boot order remains `0002,0000,0001`.

The owner approved erasing USB serial `07002AC6C31EA238` and SPCC serial
`AA231221NV01KG05237` in the coordinator conversation on November 8.
The USB was written after live serial/size/root-ancestry guards passed.
Readback of all 4,346,556,416 bytes matched the ISO SHA-256 at 23:13:25 CST.
Fresh probing reports `SUBARCHY_202611`; its FAT32 EFI partition 2 contains
the loader and Subarchy boot entry. The earlier Debian label in `lsblk`
was stale cached metadata; direct `blkid -p` identified the new image.

The parent was notified before reboot and reported its work pushed, durable
continuation on Kvant and no local parent processes. The owner confirmed
console availability. A reboot to the USB has been requested. Live boot,
trusted SSH reconnection and both SSD identities must still be checked.
The SPCC has not been erased or installed yet.

## Owner hardware acceptance

For each row, record the date, kernel and result on #75. Leave untested
rows pending. Turn reproducible failures into linked roadmap issues.
Firmware-key changes and TPM enrollment need a concrete recovery plan and
checkpoint.

| Check | Required observation | Result |
|---|---|---|
| Dual boot | Subarchy on SPCC; Omarchy still boots from firmware menu | Pending |
| NVIDIA | DKMS for both kernels; GPU modes and `subcult gpu run` | Pending |
| Wi-Fi | Connect/reconnect and usable network after reboot | Pending |
| SOF audio | Speaker/headphone output and microphone input | Pending |
| Bluetooth | Pair and use a real peripheral | Pending |
| Suspend/lid | Suspend/resume, close/open lid, unlock and network recovery | Pending |
| Battery | Unplug/replug and automatic power-profile switching | Pending |
| Splash | Graphical Plymouth and readable disk-unlock prompt | Pending |
| Secure Boot | Planned key custody/recovery, enrollment and enforced boot | Pending |
| TPM unlock | Recovery passphrase retained; successful real-TPM boot | Pending |
| DisplayLink | Attach dock; evdi/service, displays and reconnect behavior | Pending |
| Shell at 1.6 | Bar, launcher, notifications, lock and greeter usable | Pending |

Related: [[0049-installer|ADR 0049]] · [[0050-hardware-support|Hardware support]] · [[roadmap|Roadmap]] · [[review-index|Review index]]
