---
title: "First install on sputnik"
type: review
status: draft
review: pending
created: 2026-11-07
updated: 2026-11-14
tags: [review, installer]
aliases: [First install, Install runbook]
---

# First install on sputnik

Subarchy was installed on Sputnik's SPCC second drive on November 8–9,
2026 CST, coordinated from Kvant. **Both Subarchy and the existing Omarchy
booted and accepted their separately trusted SSH connections.** The owner
logged into both systems. The installer retained Omarchy as the firmware
default; the owner later selected Subarchy first on November 9, as recorded
below. Subarchy is running for owner testing.

**Reinstall, November 14:** the owner reinstalled from an image built
at main `e157cc3`. Its readback, gaps and open owner checks are in
[[#Reinstall on November 14]].

**Latest resume result, November 9 CST:** the owner completed a fresh lid
close/open cycle with a visible lock, working password input and no Hyprland
warning flash. The tested repair explicitly sets DPMS `action`, restores
lock-view focus on click/activation/Tab, and waits for the Wayland lock
notification before sleep. Gitea PR #229
merged as `aa5080e`. The owner upgraded core425 to434 at 14:17 CST;
eleven checked installed battery/lock/helper files match the qualified
package. The coordinator retired only the byte-checked temporary overrides.
The packaged idle/lock units are selected for future starts; the running,
corrected private idle process was left alone. A fresh cycle using the
packaged services and the other hardware acceptance checks remain open.

**Update feedback, November 9 CST:** core434 still briefly reports the
missing Lua file during replacement, then clears it with its final reload.
General sudo still asks for authentication, but the packaged update-specific
NOPASSWD rules explain why updates do not.
[[0069-update-authentication|ADR 0069]] records the owner's request to authenticate updates. Source fix
Gitea PR #232
adds initial authorization, a bounded-lifetime noninteractive keepalive and
watcher pause/restore around the update. These changes are not in core434;
an older updater installing them can still show the warning once. The native
watcher-setting probe passed and left the original setting unchanged.

Gitea issue #75, now [GitHub #51](https://github.com/subculture-collective/subarchy/issues/51),
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

At the installation checkpoint, normal reboots defaulted to Omarchy and
F12 **Subarchy (SPCC)** selected the new system. The owner later chose
Subarchy as the permanent default. November 9 readback on boot
`074d3320-f3c7-4653-b0fe-46cde89e3ae5` showed `BootCurrent: 0005` and order
`0005,0002,0000,0003,0004,0001,0006,0007`; the original Omarchy entry
`0002` still points to the Crucial ESP. That owner choice was left in place.
Use the Crucial/Limine entry in F12 for the Omarchy recovery path.

Re-read entry numbers before any `BootNext` or boot-order write. Subarchy's
`UEFI_BOOT_ORDER=last` avoids taking the permanent default when its entry
must be recreated.

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

Gitea issue #210 ([GitHub #99](https://github.com/subculture-collective/subarchy/issues/99)):
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

Gitea issue #211 ([GitHub #100](https://github.com/subculture-collective/subarchy/issues/100)):
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
8. Verify the protected ESP and partition map. Restore the preflight firmware
   default unless the owner explicitly changes it. Verify Omarchy's actual
   recovery boot, then use a one-time Subarchy
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
| NVIDIA | Both DKMS builds; GPU modes and `subcult gpu run` | DKMS/basic `nvidia-smi` passed. Three short offloaded Kitty launches reported NVIDIA OpenGL and exit zero; owner saw temporary disappearance, still unresolved. #218 |
| Wi-Fi | Connect/reconnect and usable network after reboot | Installed reconnect/SSH passed; owner reports Wi-Fi working November 9 |
| SOF audio | Speakers/headphones and microphone | Owner reports audio working November 9; microphone/headphones not separately identified |
| Bluetooth | Pair, use and reconnect a real peripheral | Owner reports Soma playback through Bluetooth headphones and reconnection after lid resume on November 9. Native pairing merged in #222; pairing interaction itself was not identified in this report. #217 |
| Suspend/lid | Suspend/resume, lid, unlock and network recovery | Passed November 9 after the #229 fixes: lid cycle on core 438 and standalone `systemctl suspend` on core 448, both with a visible lock and normal unlock (#213, closed). The earlier failure was a brief lock, then a black display and a reboot. Network recovery after resume was not separately checked |
| Battery | Unplug/replug and automatic profile switching | Owner confirms Dell label changes on plug/unplug after updating. Custom charging controls disappeared because firmware values remained root-only after the boot service timed out. Permission repair restored Custom 50–85% without changing it; combined-widget source adds independent charge/profile display choices. #226 |
| Splash | Graphical Plymouth and readable unlock prompt | Owner confirmation pending |
| Secure Boot | Key custody/recovery, enrollment and enforced boot | Pending; not enabled during install |
| TPM unlock | Recovery passphrase retained; real-TPM boot | Pending; no TPM token enrolled |
| DisplayLink | Dock, displays and reconnect behavior | Owner confirms dock works with lid open; lid closure leaves panel on. Source fixes #220/#223 passed regression/CI; deployment and physical retest pending, #215 |
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

### Overnight source qualification

Gitea PRs #219–#223 merged after exact-head CI on November 9:

- Gitea #219
  refreshes the Dell label when the power-profile daemon changes. Its
  isolated QML check fails on the baseline and passes with the fix.
- Gitea #220
  implements the requested docked-lid behavior and Omarchy-style scale
  shortcuts: `Super + /` increases scale and `Super + Alt + /` decreases it,
  following the [Omarchy monitor guide](https://learn.omacom.io/books/2/pages/86).
  Gitea #223
  fixes two review findings: colliding concurrent profile writes and scale
  rounding beyond 4. The same regressions fail before the fixes and pass
  afterward, including 32 writers and the 2160×1350 scale case.
- Gitea #221
  improves the greeter form, focus, small-screen scrolling and authentication
  states. A PNG rendered from the unchanged brand master includes the mark
  Qt's SVG renderer omitted. Greeter and lock share the packaged artwork;
  native Qt checks pass at scales 1, 1.6 and 2. Owner appearance acceptance
  remains on Gitea #216 (GitHub #104).
- Gitea #222
  provides native device search, pairing prompts and cancellation. Thirteen
  Gio tests use a private D-Bus daemon; the native panel fixture checks
  search ownership, PIN clearing and graceful helper shutdown. The staged
  helper also registered on Sputnik's real BlueZ and exited normally without
  pairing or discovery. Pairing/use/reconnection of an actual peripheral
  remains on #217.

The scoped code/testing review covered installer mount isolation, display
state/persistence, lock/greeter, Dell refresh, Bluetooth input/lifecycle and
the touched package/CI paths. `make verify`, focused Go race checks, QML
models/lint/index and the native tests passed. Kvant skips missing graphics
and font tools; hosted Arch checks supply separate package and shell proof.
No suspend, reboot, GPU-mode switch or desktop restart was performed during
the unattended investigation.

For #218, three owned Kitty launches ran timed three-second children and
exited zero. Debug output reported NVIDIA OpenGL 3.1/driver 615.78.08, with
context creation at 1.570 seconds, then 0.123 and 0.119 seconds. Hyprland
samples through 1.2 seconds showed mapped, unhidden windows. This limited
sampling does not establish the cause or resolution of the owner's visual
report; full GPU-mode acceptance remains pending.

Core package `0.0.0-418`, built from merged source `609b5d7`, is staged on
Kvant and Sputnik. Its SHA-256 is
`222f4d8f941e855b1c45da9e9b976c76acd1034d096b5f08ad4b2cc6036d627d`.
Package and database signatures validate against the shipped registry key
`CCE8B0F3BCDD601D909773E4466AA6E8241453D2`. The recipe hash, compiled binary's
VCS revision, eight changed source files and packaged artwork match the
qualified source. This core-file evidence is separate from parent-owned
registry-wide publishing qualification under #67.

At the overnight checkpoint the installed package was `0.0.0-1`. A guarded core-only update was
prepared: recheck SPCC root/ESP identity and the signed artifact, save the
old cached package, create pre/post snapshots, then verify that only the core
changed and the boot ID/firmware order stayed the same. `sudo -n` required
the owner's password; T3's secure file prompt was requested. No installation
secret was retained or recovered. The running shell disabled file watching,
and the existing display watcher kept its old binary, so package replacement
alone would not establish active desktop behavior. New desktop behavior and
the physical tests remained pending on #75.

### Owner update and emergency-binding recovery

The owner ran the normal updater on November 9. Installed versions are now
Subarchy `0.0.0-421`, linux-zen `7.2.14.zen1-1` and Hyprland `0.57.1-1`.
The updater reported snapshot 3, a shell restart and a required kernel
reboot. The running kernel remained `7.2.11-zen1-1-zen` on the same boot.
The earlier staged core-only update is no longer needed; do not downgrade
to package 418 or provide a password for that superseded plan.

During that update, Hyprland displayed an emergency banner saying it could
not open `default/hypr/bootstrap.lua`. The file was present again afterward,
but only three emergency bindings were registered. The configuration passed
parser validation. A user-session `hyprctl reload` returned `ok` and restored
52 normal bindings, including both scale shortcuts; the configuration-error
query was empty. No compositor restart, logout or reboot was performed.
Kvant reconnected at Wi-Fi `10.0.0.63` using the installed OS's pinned key.

The updater restarted the shell but had no final Hyprland reload after core
file replacement. The source fix reloads the caller's configuration after
the package, migrations and cleanup complete, before the shell restart.
It runs only when the core version changed, a Hyprland instance signature
is present and `hyprctl` is available. Reload failure is reported without
claiming success or skipping shell recovery. Regression checks cover the
active-session case, unchanged core, non-Hyprland calls, missing tool and
reload failure.

The updater process used to install this fix may still be the older binary.
If the banner occurs during that transition, run `hyprctl reload` once in a
terminal inside the session. Later update runs use the corrected updater.
The remaining physical checks and suspend/NVIDIA investigations stay open
on #75; this recovery does not qualify them.

### Reboot and stale update indicator

The owner rebooted on November 9. Sputnik returned over Wi-Fi with kernel
`7.2.14-zen1-1-zen`, core `0.0.0-421` and a new boot ID. The bar still showed
the count `80` saved at 02:02. Its scheduled check had not run yet: startup
checks wait 15 minutes and can add up to an hour of randomized delay.

`subcult update check --quiet --state` returned exit 2 (no updates) and wrote
`0`. The live bar's IPC then reported update-widget count `0` and
`hidden=true`, without a shell restart. The stable registry also served
core 421 at this observation. This was stale indicator data, not evidence
that the completed upgrade had failed.

The updater source now refreshes the persisted count after a successful
upgrade. It records any genuine remaining updates, accepts the no-updates
exit code and warns if checking fails. Dry runs and failed upgrades leave
the count alone. Regression tests start from the stale count 80 and cover
zero, remaining updates, check failure, dry run and upgrade failure.
An older updater used to install this fix may still need the manual check
above once; later update runs refresh the indicator themselves.

This boot also reported a failed `subcult-dell-power-permissions.service`:
the charging controls did not appear during its wait. CLI readback shows
power profiles available and charging controls unavailable. That separate
hardware/service investigation is not an update-indicator failure and
remains part of #75 follow-up.

### Battery controls and another resume failure, November 9

On core `0.0.0-425`, the owner confirms the Dell label follows plug/unplug.
The missing custom profile means custom charging thresholds. On boot
`0475fe0026414ae28605a9fdc1ae5189`, the charging attributes existed when
inspected but their current values were root-only. The permission service
had stopped after five seconds waiting for those attributes. After the
owner rebooted to `988359811d6d4a2fb5f6361808cfa366`, restarting that service
succeeded. User-level CLI readback restored **Custom, start 50%, stop 85%**;
root readback before and after showed the same mode and values. No charging
policy was changed. A longer startup wait and graceful handling of absent
optional controls have regression coverage; a subsequent boot with the new
helper is still needed for #226.

The combined battery panel includes Dell power/charging controls and two
independent persisted display choices: charge icon or icon with percentage;
profile off, icon, or icon with text. Legacy Dell layout IDs resolve to one
battery entry in memory. Firmware controls and the generic non-Dell profile
fallback remain separate capabilities within that panel.

The owner also reports Bluetooth headphone playback before lid closure,
disconnection during sleep, reconnection and resumed audio on opening the
lid, followed by a brief lock screen and black display. A previous attempt
showed three failed unlock attempts but did not accept input. Logs from the
11:57 CST attempt show suspend at 11:57:54, resume at 11:58:00 and shutdown
at 11:58:08. The lock remained alive until shutdown; its video decoder
started on resume and Wayland warned about disabling an unfocused text-input
surface. Neither message establishes the cause. #213 remains open.

### Standalone suspend, November 9 evening

The owner ran `systemctl suspend` from a terminal on core 448 and reports
that it worked as expected. Read-only readback from Kvant, boot
`b0b0f47cad0341fe9a6bcada4224895e`, kernel 7.2.14-zen1-1-zen: s2idle entry
at 19:57:30 CST and exit at 19:57:37 with no lid event; the lock unit ended
with `Result=success` and no restarts; no failed system or user units. The
17:48 lid cycle on the same boot is in the same journal. With the lid result
above this meets #213's acceptance, and the issue is closed. The crash
restart policy of the lock stays in #230.

## Reinstall on November 14

The owner reinstalled Subarchy on the SPCC disk on November 14, 2026 from an
ISO built at main `e157cc3`, SHA-256
`3107bd6a3ef5244592b3a6be4c8a1ee0504af422557a32c9e0022ff749cc0c4c`. The
installer finished at 12:23 CST with core `0.0.0-588` and 1,038 packages
(`/var/log/subarchy-install.log`). The owner then updated to core
`0.0.0-590`. The Crucial disk still holds Omarchy's ESP and closed LUKS
partition, and its firmware entry `0002` remains.

The results below were read from Kvant over SSH at 13:37 CST, 69 minutes
after boot, while the owner was using the laptop. Only read-only commands
ran: no sudo, no setting changed, no process stopped. Anything that needs
root (`ufw status`, LUKS tokens, the contents of `/boot`) was not read. The
acceptance table above records the first install; this install's results
are here until the owner retests.

### What the readback shows

**Boot.** Kernel `7.3.4-zen2-1-zen`; `linux-lts 6.18.63-2` and Hyprland
`0.57.2` are installed (`uname -r`, `pacman -Q`). The command line carries
`quiet splash` and the AppArmor LSM list (`/proc/cmdline`). `bootctl status`:
Limine 12.9.6 started `/EFI/Linux/subarchy_linux-zen.efi`, entry
`Subarchy.linux-zen`, from the new 4 GiB ESP (PARTUUID
`32e6caf8-49b4-4355-9f55-1ce2a9f9f358`, 976 MiB used). `efibootmgr`:
`BootCurrent: 0007`, order `0007,0002,0000,0006,0004,0001,0003`. The
installer put `0007` first and removed `0005` "Limine", which pointed at
ESP `ce2275ae-…` (the `efibootmgr` listing in
`/var/log/subarchy-install.log`). That ESP is neither the November 9 one
(`d5d15d48-…`, whose entry `0005` was labelled "Subarchy (SPCC)") nor
today's, so at least one more install ran on the SPCC disk between November 9
and today; how many is for the owner to say. The firmware fallback `0004`
also pointed at `ce2275ae-…` before the install and now points at today's
ESP. Both `0002` (Omarchy) and `0007`
(Subarchy) are labelled `Limine`, so the F12 menu shows the same name twice.
`0003` "Linux Firmware Updater" still points at the first install's ESP
`d5d15d48-…`, which is gone; the installer only prunes entries named Limine
or Subarchy.

**Boot time (checklist F2).** `systemd-analyze`: firmware 6.411 s + loader
10.036 s + kernel 0.900 s + initrd 15.349 s + userspace 5.036 s = 37.735 s;
`graphical.target` after 4.350 s of userspace. In
`journalctl -b -o short-monotonic`, Plymouth starts 1.06 s after the kernel.
"Load Kernel Modules" runs from 0.98 to 2.70 s: NVIDIA module insertion
starts at 1.04 s (`nvidia: loading out-of-tree module taints kernel`) and
ends with `nvidia_drm` at 2.70 s. Root cryptsetup starts at 2.71 s, right
after it finishes, and the passphrase request reaches Plymouth at 2.73 s. So
about 1.7 s of the 2.73 s between kernel start and the prompt is the NVIDIA
modules in the initrd. The disk unlocked at 13.9 s, so most of the initrd
time is passphrase entry. The rest of the black gap falls in the 10 s loader
phase, which also covers Limine's 3 s menu timeout. The NVIDIA modules make
the UKI larger and may add to that phase too; `/boot/EFI/Linux/` is
root-only and its sizes were not read. The gap itself needs a stopwatch, so F2 stays
open. `systemd-analyze blame` is led by device units at 15.7 s (TPM, serial
ports) that wait for the unlock; the slowest services were `fwupd` 2.213 s,
`subcult-ufw-docker` 1.654 s, `ldconfig` 1.145 s (first boot after the
install), `thermald` 0.858 s and `intel_lpmd` 0.780 s. The critical chain
runs through `subcult-ufw-docker` and `power-profiles-daemon`.

**Units and journal.** `systemctl --failed` and `systemctl --user --failed`
list nothing; `hyprctl configerrors` is empty and 55 bindings are
registered. Errors this boot (`journalctl -b -p err`), by unit:

- kernel, 6: TDX not supported; `ucsi_acpi` `UCSI_GET_PDOS failed (-5)`
  with "unknown error 0", twice each.
- `wpa_supplicant`, 2: nl80211 does not support multicast RX registrations.
- `intel_lpmd`, 1: cannot open `/proc/sys/kernel/sched_itmt_enabled`.
- `sddm`, 1: `gkr-pam: unable to locate daemon control file`.

Warnings: 152 from the kernel, 129 of them ufw blocking inbound multicast on
Wi-Fi. The rest: the USB stick's GPT backup header (normal for a written
ISO); a dirty FAT bit on Omarchy's ESP, logged when fwupd mounted it through
udisks 34 minutes after boot; one `snd_hda_intel` stream DMA error; the
NVIDIA taint and `nvidia-drm` "Cannot find any crtc" (the dGPU drives no
output); a WMI firmware-bug note. The user manager logged 26, among them
the Qt Wayland text-input "Trying to disable … but … is focused" 11 times
(the message from the November 9 resume logs), a keyring item already registered
4 times, xdg-desktop-portal finding no RealtimeKit 3 times (`rtkit` is not
installed), and portal app-ID and parent-window warnings. Other units: the
Bluetooth configuration directory mode differs from the unit's, D-Bus could
not activate `org.freedesktop.home1`, and NetworkManager could not set IPv6
forwarding on the P2P device. A T3 Code user unit the owner added failed
three times while it was being set up and then ran.

**NVIDIA.** `lspci -k`: Iris Xe on `i915`, RTX 3050 Ti Mobile on `nvidia`.
Driver `620.70.06`, built by DKMS for both kernels (`dkms status`).
`nvidia-smi` lists the GPU at P8. Over SSH, `subcult gpu mode` prints
`chosen: intel` and `running: unknown (not a hybrid session)`, because SSH
lacks the session environment. Hyprland's environment has
`SUBCULT_GPU_MODE=intel` and `AQ_DRM_DEVICES=/dev/dri/subcult-igpu`, and
Hyprland holds only `card1` and `renderD128`, the Intel nodes. Two faults:

- `/dev/dri/subcult-igpu` points at `card0`, the NVIDIA card, as does
  `subcult-dgpu`; `udevadm info` lists `subcult-igpu` on both cards. The rule
  in `default/system/gpu.rules` matches `ATTRS{vendor}=="0x8086"` on any
  parent, and the NVIDIA card sits behind an Intel PCIe root port
  (`0000:00:01.0`). The link was rewritten at 13:02, when the udev reload hook
  ran during the owner's `pacman -Syu`. The session started at 12:29 on the
  Intel card; the next login may start Hyprland on the NVIDIA card in Intel
  mode.
- The dGPU never powers down. `power/runtime_status` reads `active`,
  `power/control` reads `on`, and `/proc/driver/nvidia/gpus/…/power` says
  `Runtime D3 status: Disabled by default`. [[0006-gpu-drivers|ADR 0006]]
  records `Enabled (fine-grained)` for this GPU. This is checklist P9's
  check, read on AC and undocked, not on battery; with `control` at `on` the
  card cannot suspend at all.

**Wi-Fi.** Intel AX211 on `iwlwifi`. `nmcli device` and `iw dev … link`:
connected on 5 GHz at 160 MHz (HE), signal −41 dBm, transmit 2401.9 Mbit/s.
No wired interface was present; the dock was not attached.

**Audio.** One card, HDA Intel PCH. The kernel picked `snd_hda_intel` with
the Realtek ALC289 codec, not SOF (`snd_intel_dspcfg` `dsp_driver=0`, auto),
although `sof-firmware 2026.09.2-1` is installed and `subcult hw info`
matches `intel-sof`. `wpctl status` shows one sink and one source, both
"Built-in Audio Analog Stereo"; the source is the analog `front:0` device.

**Bluetooth.** `bluetooth.service` active; `bluetoothctl show`: powered,
not discoverable, not pairable; no paired devices. The reinstall dropped the
November 9 pairings.

**Battery.** On AC, `BAT0` at 86 % and "Not charging"; charge type Custom,
start 50 %, stop 85 %. The Dell attributes `PrimaryBattChargeCfg`,
`CustomChargeStart` and `CustomChargeStop` are mode 660, group `wheel`, and
`subcult-dell-power-permissions` ended with `Result=success`.
`powerprofilesctl get`: `balanced`.

**Splash.** `/etc/plymouth/plymouthd.conf` sets `Theme=subarchy`, and the
journal shows the initrd starting Plymouth and passing the passphrase request
through it. Whether the splash was graphical and readable is for the owner's
eyes.

**Secure Boot and TPM.** `bootctl status`: Secure Boot disabled, TPM2
support yes, measured UKI yes. `sbctl status`: setup mode disabled, Secure
Boot disabled, no sbctl keys, Microsoft and built-in vendor keys.
`/sys/class/tpm/tpm0` is TPM 2.0 and `systemd-analyze has-tpm2` says yes.
Reading the LUKS tokens needs root, so TPM enrolment was not checked.

**Disks.** `lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINTS`: the SPCC disk is now
`nvme1n1`, with a 4 GiB vfat ESP at `/boot` and a LUKS2 partition holding the
btrfs root, mounted at `/`, `/home`, `/var/log` and `/var/cache/pacman/pkg`.
The Crucial disk is `nvme0n1`, with its 2 GiB ESP and a LUKS partition that
is not open. Swap is 15.5 GiB of zram.

**DisplayLink.** The USB devices in sysfs are the webcam, fingerprint
reader, Bluetooth and the root hubs; `lsusb` is not installed. No adapter was
attached at install, so hardware detection skipped `evdi-dkms` and
`displaylink`: `modinfo evdi` finds no module and `displaylink.service` does
not exist. Both packages are in `[subarchy]` (`evdi-dkms 1.15.1-1`,
`displaylink 6.4-1`). If the dock is a DisplayLink device (B5), its panels
stay dark until they are installed.

**Display.** `hyprctl monitors` in the owner's session: one monitor, `eDP-1`,
3456×2160 at 60 Hz, scale 2. The shell has not been tried at 1.6.

**Hardware detection.** `subcult hw info`: Dell XPS 15 9520, hybrid; matches
`display fingerprint hybrid-gpu intel intel-sof laptop nvidia nvidia-gsp
touchpad touchscreen vulkan webcam x86`. `subcult hw fixes` lists
intel-lpmd, intel-video, nvidia-modeset and dell-power (untested) and
hid-apple-fkeys (tested). Every package `subcult hw packages` names is
installed; `subcult hw services` names `intel_lpmd`.

**Packages.** `pacman -Q | wc -l`: 1,053, of which 176 explicit. The
installer installed 1,038; the owner added 15: `base-devel` with 13
dependencies, and T3 Code.

### Gaps found on this install

- No `hostname` command; fixed after this image by #189 (`inetutils`).
- No screenshot binding: `hyprctl binds` has none for Print, grim or slurp,
  although `grim` and `slurp` are installed.
- T3 Code desktop is not preinstalled: `t3code-nightly-bin` is still in
  `PENDING` in `tools/test/apps-preinstalled-test.py`. The owner built it
  from the AUR with makepkg at 12:49.
- Neither `yay` nor `base-devel` was installed. The owner added
  `base-devel` at 12:47; `yay` is still absent.
- The installer left an unsigned `[subarchy]` sync database; fixed after this
  image by #187.
- From the readback above: `subcult-igpu` can point at the NVIDIA card; the
  dGPU never reaches runtime D3; DisplayLink drivers are missing when no dock
  is attached at install; both Limine firmware entries share a label and a
  stale "Linux Firmware Updater" entry remains; `lsusb` (checklist B5) is
  not installed.

### Still needs the owner

Matching #51's list, with the [[test-checklist|checklist]] items:

- NVIDIA modes and `subcult gpu run` (P8, P9 on battery, P10). Check where
  `/dev/dri/subcult-igpu` points before the next login.
- Wi-Fi reconnect after reboot and the network panel (F6, N1).
- Speakers, headphones and microphone (A1).
- Bluetooth pairing, use and reconnection (A2–A5).
- Suspend, lid and unlock (section 5).
- Battery unplug/replug and profile switching (P1).
- The graphical splash and the length of the black gap (F2, F3).
- Secure Boot (F12) and TPM unlock (F13, F14).
- The DisplayLink dock (M2–M5), after its drivers are installed.
- The shell, lock and greeter at scale 1.6 (M1, F10).
- How many installs ran on the SPCC disk between November 9 and today (one
  left ESP `ce2275ae-…`).

Related: [[0049-installer|ADR 0049]] · [[0050-hardware-support|Hardware support]] · [[package-publishing|Package publishing]] · [[roadmap|Roadmap]] · [[review-index|Review index]]
