---
title: "First install on sputnik"
type: review
status: draft
review: pending
created: 2026-11-07
updated: 2026-11-09
tags: [review, installer]
aliases: [First install, Install runbook]
---

# First install on sputnik

Subarchy was installed on Sputnik's SPCC second drive on November 8–9,
2026 CST, coordinated from Kvant. **Both Subarchy and the existing Omarchy
booted and accepted their separately trusted SSH connections.** The owner
logged into both systems. Subarchy is running for owner testing; Omarchy
remains the permanent firmware default.

Issue [#75](https://git.subcult.tv/subculture-collective/subarchy/issues/75)
stays open until the owner records the remaining hardware results below.
Installation, local checks, hosted CI, package publication and physical
acceptance are separate claims.

## Installed system

The installed desktop includes the Quickshell bar, launcher, notifications,
widgets, standalone lock, themed screensaver, SDDM and Hyprland. Kitty and
Neovim with the packaged configuration are installed. Additional apps come
through `subcult app install`; the catalog is not an installation receipt.

The base includes LUKS2, btrfs subvolumes and snapshots, linux-zen and
linux-lts, Limine, zram, NetworkManager, PipeWire, Bluetooth, AppArmor and
ufw. Hardware detection selected Intel/NVIDIA firmware and microcode,
NVIDIA open DKMS and both kernel headers. OpenSSH and the DisplayLink
packages/service were provisioned for this workstation's access and dock
tests. No DisplayLink adapter was attached; dock behavior is untested.

Observed on November 9 at 00:03–00:05 CST:

- Subarchy: `ID=subarchy`, kernel `7.2.11-zen1-1-zen`, firmware entry
  `0005` labelled **Subarchy (SPCC)**.
- Root btrfs UUID `d02d895a-5cd1-4fe9-822f-069ce1e21f33`, subvolume
  `@`, backed by the SPCC LUKS2 UUID
  `1b3aee4a-ede2-4d97-b885-26f6681afffa`.
- Its own 4 GiB ESP: PARTUUID
  `d5d15d48-5033-4721-915e-887a8ddaf220`. The remaining partition is
  995,908,853,248 bytes. Both UKIs and the read-only `@factory` snapshot
  were checked before boot.
- SSH, NetworkManager, SDDM, ufw and DisplayLink services active; no failed
  system or user units after the power dependency repair.
- The saved Wi-Fi profile reconnected automatically. Its interface-name
  restriction was removed to tolerate live `wlan0` versus installed
  `wlp0s20f3`. It is root-owned mode 600; credentials are not in this repo.
- ufw denies incoming connections by default; its SSH exception allows
  only Kvant's verified LAN address.
- NVIDIA `615.78.08` and evdi `1.15.1` DKMS modules are installed for
  `7.2.11-zen1-1-zen` and `6.18.57-2-lts`. `nvidia-smi` sees the
  RTX 3050 Ti Laptop GPU. This does not establish GPU modes or rendering.
- Shell and idle user services active; Hyprland configuration errors empty.
  Quickshell loaded its configuration. Two portal app-ID warnings were
  logged; no visible portal workflow was tested.
- Secure Boot was not enabled and no TPM token was enrolled.

The core package is still the image's `subarchy 0.0.0-1`. The merged
PR #209 channel-registration logic was built from
`72314a1197f204e568657167eb534ee032ddfa10` and run once as a temporary
helper. `[subarchy]` now requires package and database signatures and
includes `/etc/pacman.d/subcult-repo`. The helper was removed; no
package-owned binary was replaced by hand. The unsigned bootstrap sync
database was moved into private recovery storage, not retained under the
signed repository name. The first signed published core upgrade and
online-update qualification remain parent-owned under #67. A client database
sync with signatures required passed, but the core package was not present
in the repository at the time of that check.

## Disk identities and the boot-order trap

Device numbering changed twice. **Never select a disk by NVMe number.**

| Role | Model | Serial | Capacity | Before USB boot | Live installer | Installed Subarchy |
|---|---|---|---|---|---|---|
| Subarchy | SPCC M.2 PCIe SSD | `AA231221NV01KG05237` | 1,000,204,886,016 bytes | `nvme0n1` | `nvme1n1` | `nvme0n1` |
| Retained Omarchy | CT1000P5PSSD8 | `222839D04356` | 1,000,204,886,016 bytes | `nvme1n1` | `nvme0n1` | `nvme1n1` |
| Installer USB | USB DISK 3.0 | `07002AC6C31EA238` | 62,025,367,552 bytes | `sda` | `sda` | `sda` |

The guarded install used these stable paths:

```text
/dev/disk/by-id/nvme-SPCC_M.2_PCIe_SSD_AA231221NV01KG05237
/dev/disk/by-id/nvme-CT1000P5PSSD8_222839D04356
/dev/disk/by-id/usb-_USB_DISK_3.0_07002AC6C31EA238-0:0
```

Pre-install observation on November 8: the SPCC had an empty GPT with no
partitions/mounts; the USB held a Debian 13.7 installer. The owner approved
erasing both exact serials. Immediately before formatting, guards checked
all three identities/capacities, no SSD mounts or active mappings, no swap,
an empty target mountpoint and the live overlay root. Omarchy stayed closed
and unmounted during installation, apart from temporary read-only ESP
hash checks.

Omarchy recovery boot was observed at 23:52 CST: kernel
`7.2.15-1-omarchy`, original root UUID
`4f537c0d-73ef-49cf-900e-9bb790d89001`, Crucial serial
`222839D04356`, firmware entry `0002`. Its LUKS UUID remains
`9ed35003-158c-46d6-bb75-d896f4ed5c04`.

Observed firmware order after the Omarchy recovery boot started with Omarchy:
`0002,0000,0003,0001,0005,0004`. Firmware automatically added a generic
SPCC fallback entry `0004` on reboot. Entry `0005` is the distinct
Subarchy Limine path on the new ESP; the existing Crucial entries remain.
In-place relabelling with `efibootmgr -b -L` did not change the label, so
only the newly created SPCC entry was recreated with the distinct label.
GUID and loader-path readback guarded that operation.

Future normal reboots still default to Omarchy. Use F12 and select
**Subarchy (SPCC)** to return to Subarchy. Re-read entry numbers before any
`BootNext` or boot-order write. Subarchy's `UEFI_BOOT_ORDER=last` avoids
taking the permanent default if its entry must be recreated.

## Artifact and recovery receipts

The installed artifact was built on Sputnik from source
`144cdf27ff561b18d6187606fecbc61406d5910c` (#207). Main advanced to #208
during the build; that diff changed only CI/docs. The changed core package
was rebuilt. Reused non-core package recipes matched cache source
`35b3058`; manifests record all 635 repository package files.

- ISO: `subarchy-2026.11.08-x86_64.iso`, 4,346,556,416 bytes.
- ISO SHA-256:
  `84de29b725a4e311ca13817cccacf1fa197729c3e9bbd4fb25d3e1d5fcee8c31`.
- Core package SHA-256:
  `f69eba323240ae3b6e4bec4ced369fac6849f07969bb91faedd1204a0bd0396c`.
- Fresh live boot: **PASS**, five checks.
- Strict key-only SSH from Kvant to the live VM: **PASS**.
- Guided offline install from that exact image: **PASS**, 262 seconds
  with the VM network disabled.
- Complete VM run: **78 checks passed, 0 failed, exit 0**, including
  snapshots and emulated Secure Boot/TPM. Post-install VM checks enable
  networking; these results do not qualify physical hardware.
- Physical USB write: full readback matched the ISO hash at 23:13:25 CST.
  Direct probing showed `SUBARCHY_202611`; the earlier Debian label in
  `lsblk` was stale cached metadata.

Kvant's private `~/.local/state/subarchy-install-75/` holds the independent
ISO copy, manifests, logs, live guards and actual boot proofs. Its
`recovery/` holds Omarchy's ESP archive, LUKS header and partition/firmware
evidence; `real-install/` includes the new LUKS header and install/boot
receipts. All 15 archived ESP file hashes matched preflight. After the live
boot, only the 32-byte `loader/random-seed` differed; the other 14 boot
files still matched. Before installation it received a separate explicit
baseline. All 15 files matched that baseline after installation, and the
Crucial partition map was unchanged.

The seed change is consistent with
[systemd's documented boot-seed rotation](https://www.freedesktop.org/software/systemd/man/latest/systemd-boot-random-seed.service.html).
Its exact writer was not identified; the live userspace service reported
no ESP. Do not restore an old random seed to hide a hash difference.

These are boot-recovery copies, not a full Omarchy user-data backup. Keep
archives, encrypted-volume headers, network credentials and the personalized
access-enabled ISO private. Real account/disk secrets came through separate
secure cards and were used from owner-only RAM files, never VM credentials.
The live files were removed before reboot; Kvant's temporary password files
were removed after the final checks. The dedicated SSH key remains private.

## Install findings and repairs

[Issue #210](https://git.subcult.tv/subculture-collective/subarchy/issues/210):
the image's installer completed the base system and factory snapshot, then
exited 5 at its final LUKS close. Live-service mount namespaces retained
`/mnt/run` and later serial-getty credential submounts. Only those
installer subtrees were unmounted; the mapping open count fell from 1 to 0
and close succeeded. No destructive stage was repeated and no service was
stopped. Access provisioning in an outer private mount namespace closed
cleanly.

The source fix isolates the whole installer before any mounts. The root-only
probe `sudo bash tools/test/installer-mount-test.sh` reproduces the old
retained mount and passes with isolation using a private tmpfs tree. Local
`make verify` passed. The ISO recorded above predates this fix; a rebuilt
fixed ISO has not been qualified.

[Issue #211](https://git.subcult.tv/subculture-collective/subarchy/issues/211):
`powerprofilesctl` could not import `gi.repository`, so automatic power
selection failed on the real battery-equipped laptop. The no-battery VM
path had bypassed that import. Installing `python-gobject 3.58.1-1` and its
two missing dependencies repaired the CLI and service: `Result=success`,
`ExecMainStatus=0`, AC profile `balanced`, no failed units. The source
package now requires the daemon and bindings; VM qualification also invokes
the CLI without a battery. Physical unplug/replug remains untested.

The ufw exception was written before its chroot command tried to reload the
live firewall and returned an error. Its on-disk rule was checked, and the
real installed boot subsequently loaded ufw with the intended Kvant-only
exception. This was access-provisioning recovery, not a claimed clean
installer exit.

## Procedure for a repeat install

1. Build from pinned current main in an independent checkout. Check space,
   use a unique `SUBARCHY_ISO_WORK`, record source/overlay/package hashes,
   and qualify the exact image with live-boot and guided offline tests.
2. Identify USB and SSDs by model, serial, capacity, mount ancestry and
   holders. Present a concrete erase plan and obtain the owner's destructive
   checkpoint. Revalidate identities after reboot; do not ask again for the
   same approved identities merely because device numbers changed.
3. Preserve private boot-recovery copies and existing firmware trust.
   Prepare distinct live/installed SSH identities and network continuity.
   Notify the parent before reboot; keep its work durable on Kvant.
4. Write only the approved USB, flush and read back all ISO bytes. Boot it,
   connect Wi-Fi locally if needed and establish trusted live SSH.
5. Obtain real passwords through secure cards and keep files mode 600 in
   live RAM. Install only to the approved by-id disk, with its own ESP and
   LUKS2/btrfs remainder. Keep the other encrypted disk closed.
6. Use the fixed installer's private mount namespace. If recovering an
   older image's final-close failure, inspect mount namespaces and saved
   logs; never rerun partitioning to repair cleanup.
7. Provision only the new OS's SSH key, Wi-Fi profile and restricted
   firewall rule. Do not migrate Omarchy's home, T3 or VPN identity.
   Generate/pin new host keys and check package/service state.
8. Verify the protected ESP and partition map. Restore Omarchy's firmware
   default. Verify its actual recovery boot, then use a one-time Subarchy
   boot and finish there. The owner unlocks the corresponding disk locally.
9. Verify new root/ESP ancestry, trusted SSH, units, session and receipt
   source. Apply merged client fixes separately from the image; require
   signature verification before claiming published updates work.
   Remove temporary credential files after use.

## Owner hardware acceptance

Record date, kernel and observations on #75. Leave untested rows pending;
turn reproducible failures into roadmap issues. Secure Boot/TPM changes
need their own key-custody and recovery checkpoint.

| Check | Required observation | Result |
|---|---|---|
| Dual boot | Subarchy on SPCC; original Omarchy boots via its firmware entry | Passed November 8–9 |
| NVIDIA | Both DKMS builds; GPU modes and `subcult gpu run` | DKMS/basic `nvidia-smi` passed; owner saw only offloaded Kitty disappear temporarily, duration unknown. Inconclusive, #218 |
| Wi-Fi | Connect/reconnect and usable network after reboot | Installed reconnect/SSH passed; owner reports Wi-Fi working November 9 |
| SOF audio | Speakers/headphones and microphone | Owner reports audio working November 9; microphone/headphones not separately identified |
| Bluetooth | Pair and use a real peripheral | Discovery observed; no pairing attempted. Panel delegates pairing to terminal, #217 |
| Suspend/lid | Suspend/resume, lid, unlock and network recovery | Failed: lock appears briefly, then black display; owner reboots. #213 |
| Battery | Unplug/replug and automatic profile switching | Owner confirms changes take effect; Dell label stays stale until interaction, #214 |
| Splash | Graphical Plymouth and readable unlock prompt | Owner confirmation pending |
| Secure Boot | Key custody/recovery, enrollment and enforced boot | Pending; not enabled during install |
| TPM unlock | Recovery passphrase retained; real-TPM boot | Pending; no TPM token enrolled |
| DisplayLink | Dock, displays and reconnect behavior | Owner confirms dock works with lid open; lid closure leaves panel on, #215 |
| Shell at 1.6 | Bar, launcher, notifications, lock and greeter usability | Owner accepts scaling appearance and display output; live scale was 2, so 1.6 remains pending. Scale shortcut #215; greeter appearance #216 |

### November 9 owner follow-up

The requested dock behavior is to keep external displays on and turn off
the laptop panel when the lid closes. Restore the panel on reopening and
retain a usable display if the dock is removed. The requested scale
shortcut should follow Omarchy's display controls.

The failed suspend at 00:23 CST used boot `cd91287eb3054e9ea1c8001eaba9942e`.
System logs show s2idle entered at 00:23:37 and resumed at 00:23:41;
hypridle's DPMS-on command returned `ok`. The lock process remained alive
and received keyboard/PAM requests. The kernel logged `spd5118` resume
errors and NVIDIA ACPI D-Notifier messages. These are diagnostic leads;
the cause of the black display is not established. The machine exposes
only s2idle. No remote suspend/reboot or driver-setting experiment was
performed during this investigation.

Kvant reconnected through dock Ethernet `10.0.0.64` using the installed
OS's pinned SSH key. Its separate coordinator config was updated; the
global Omarchy alias and the owner's Wi-Fi connection were left alone.

Issues #213–#218 track the failures, inconclusive GPU result and requested
interface improvements. They do not count as completed physical retests.

Related: [[0049-installer|ADR 0049]] · [[0050-hardware-support|Hardware support]] · [[package-publishing|Package publishing]] · [[roadmap|Roadmap]] · [[review-index|Review index]]
