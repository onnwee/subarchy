---
title: "Release notes 0.0.0"
type: review
status: draft
review: pending
created: 2026-11-20
updated: 2026-11-20
tags: [review, release, hardware]
aliases: [Release notes, 0.0.0 release notes]
---

# Release notes 0.0.0

Draft release notes for the first Subarchy release, version `0.0.0`
([[0066-versioning|ADR 0066]]). Written 2026-11-20 for issue #279, as a
draft the owner reads before #84 closes (checklist Q21 in
[[test-checklist]]).

**This is a draft, not the release notes.** The release commit is not
chosen. Everything marked **FILL AT TAG** is empty on purpose and must be
filled from the tagged build, not from the candidate below. The hardware
lines are final only after the owner session (#275); until then each row
says what was recorded and what is still pending.

How to read the claims. Every statement names an issue comment, a CI run or
a repository document, with its date. Dates are UTC unless marked CST. A
comment that was moved from Gitea to GitHub on 2026-11-10 carries the date
it was first written. This note records what those sources say; it does not
add a result of its own.

## Release identity

| Field | Value |
|---|---|
| Version | `0.0.0` ([[0066-versioning\|ADR 0066]]) |
| Release commit | **FILL AT TAG:** full commit hash on `main` |
| Core package release | **FILL AT TAG:** `subarchy-0.0.0-<release>` (the release number is the commit count) |
| Arch snapshot on the stable channel | **FILL AT TAG:** `YYYY/MM/DD` |
| Verify run | **FILL AT TAG:** run id, attempt and result |
| Package run | **FILL AT TAG:** run id, attempt and result |
| ISO run | **FILL AT TAG:** run id, attempt, and live plus installed check counts |
| ISO size and SHA-256 | **FILL AT TAG:** bytes and hash of the release image |
| Hardware results taken on | **FILL AT TAG:** core release and kernel of the install the owner session used |
| Owner sign-off | **FILL AT TAG:** date and issue comment (#84) |

Where to obtain the ISO is not stated here; the choice is open (#259). The
ADR 0053 licence gate is not recorded as passed here; the ruling is open
(#261, #84).

## Last fully qualified build

The last build that passed the full set of checks is main `9e32591`, core
`0.0.0-638`, Arch snapshot `2026/11/15`. It is **not** the release
candidate: on 2026-11-20 the owner lifted the hold on merges, so main moves
past it and the release needs its own runs
([#84 comment, 2026-11-20 15:04](https://github.com/subculture-collective/subarchy/issues/84#issuecomment-7042864244)).
It is the build installed on Sputnik on 2026-11-16, so it is the build the
hardware results below were taken on.

What the 2026-11-16 receipt on #84 records for `9e32591`
([#84 comment, 2026-11-16 17:28](https://github.com/subculture-collective/subarchy/issues/84#issuecomment-6923894528)):

| Check | Result |
|---|---|
| Gitea run 23108, ISO job 44226, attempt 1 | Passed. Retained evidence shows 6 live plus 118 installed, 124 runtime checks |
| Gitea run 23109, packages | Publish job 44239, attempt 2, passed at 17:25:24. Stable and edge verified in a fresh container, then a normal online install of 255 packages that installed core `0.0.0-638` |
| Gitea run 23109, publish job 44228, attempt 1 | Failed: publication passed, then registry transfers for two packages reset at 17:07:46. Recorded as a transient transport failure; no origin or client cause was established |
| Gitea run 23110, source verify | Attempt 2 passed (verify 44232, package 44233, shell 44234) |
| ISO identity | 7,099,686,912 bytes, SHA-256 `4fc180fc1615a255f1e48bc4013c7a5acefabbe16dfb94b996fa45d5f4d1ff90`, from the source-bound capture receipt. The follow-up on 2026-11-16 did not rehash it |

The same comment says the CLI prints `subcult 0.0.0`; `638` is the package
release, not the CLI version.

## Tested hardware

One machine: a Dell XPS 15 9520 (Sputnik), BIOS 1.44.0, with an Intel
Iris Xe and an NVIDIA RTX 3050 Ti hybrid GPU pair
([#249, 2026-11-17](https://github.com/subculture-collective/subarchy/issues/249),
[#195, 2026-11-16 21:08](https://github.com/subculture-collective/subarchy/issues/195#issuecomment-6929383535)).
Subarchy is installed on the SPCC M.2 SSD, serial `AA231221NV01KG05237`;
Omarchy stays on a separate Crucial SSD
([#51, 2026-11-08](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6782833085)).

No other machine has run Subarchy. Nothing else is tested.

### Results on core `0.0.0-638`

Installed 2026-11-16 (owner report,
[#51, 20:11](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6927921652)).
Kernel `7.3.4-zen2-2-zen`, NVIDIA driver `620.70.06`, from the read-only
readback that evening
([#51, 20:38](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6928690350)).
The last column is
the pending owner session #275; its steps are from the runbook on
[#51, 2026-11-20](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-7033827474),
which that comment says had not been run. Since the hold was lifted, the
release candidate is a later build, and Sputnik needs it installed before
or at that session
([#84, 2026-11-20 15:04](https://github.com/subculture-collective/subarchy/issues/84#issuecomment-7042864244));
the rows below describe core 638 only.

| Row | Result recorded | Source | Owner session #275 |
|---|---|---|---|
| Boots from the SPCC disk | Passed. Installed system readback: root is btrfs `@` through the LUKS mapping on the SPCC disk | [#51, 2026-11-16 20:38](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6928690350) | Not repeated |
| Failed units after install | None, system or user | same | Pending, step 6.1 |
| Intel and NVIDIA OpenGL | Passed. Default context on Intel Iris Xe; explicitly offloaded context on the RTX 3050 Ti. Two context paths only, not every GPU mode | [#51, 2026-11-16 21:07](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6929359466) | Pending, steps 3.1 to 3.8 |
| NVIDIA mode switch | Not tested | same | Pending, steps 3.1, 3.2, 3.7 and 3.8 |
| NVIDIA runtime power on battery (P9) | **Failed** on Zen. See [[#Known limitations]] | [#195, 2026-11-17](https://github.com/subculture-collective/subarchy/issues/195#issuecomment-6936334494) | Pending, steps 1.5, 1.14 and 2.1 to 2.3 |
| Wi-Fi | Connected, zero RX and TX errors in a short sample. Reconnect after reboot not recorded | [#51, 2026-11-16 21:07](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6929359466) | Pending, step 1.16 timing only |
| Speakers | Passed. The owner heard two notes | same | Pending, step 1.10 |
| Microphone and headphones | Not tested | same | Pending, step 1.10 |
| Bluetooth | Not tested. The adapter is powered; no peripheral was paired | same | Pending, step 1.11 |
| Lid close, wake and unlock | Passed. Kernel log: `PM: suspend entry (s2idle)` at 01:58:37 and `suspend exit` at 01:58:48, about 11.8 s apart; the owner unlocked and the desktop returned. An earlier owner-reported cycle at 00:31 has no kernel markers | [#51, 2026-11-17 02:05](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6935670883), [00:33](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6933854721) | Pending, steps 1.12, 1.14 and 2.3 |
| Suspend from the power menu | Not tested | [#51, 2026-11-17 02:05](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6935670883) | Pending, step 1.16 |
| Battery profile switching | Not tested. UPower reports a wrong power source (#249) | [#51, 2026-11-17 02:40](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6936334862) | Pending, steps 1.7 and 1.8 |
| Graphical splash | Not observed | [#51, 2026-11-20 runbook](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-7033827474), [[first-install#Results on core 638]] | Pending, steps 1.4 and 4.8 |
| Secure Boot | Not tested on hardware. Disabled on this install | [#51, 2026-11-16 20:38](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6928690350) | Not in the session (#268) |
| TPM unlock | Not tested on hardware. One TPM present, no LUKS token enrolled | [#51, 2026-11-16 21:07](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6929359466) | Not in the session (#268) |
| DisplayLink dock | Not tested. No DisplayLink device was enumerated | same | Pending, steps 3.3 to 3.9 |
| Shell at scale 1.6 | Not tested. The panel ran at scale 2 | same | Pending, steps 3.1 and 3.2 |
| Retained Omarchy boots | Not observed on this install. A Crucial firmware entry is present | same | Pending, step 4.7 |
| Linux LTS boot | Not booted on this install. NVIDIA DKMS is installed for both kernels | same | Pending, steps 2.1 to 2.3 |
| Fingerprint reader | Not tested on this install | [[first-install#What the reinstall reset]] | Pending, steps 1.9 and 1.12 |
| Google calendar (#89) | Not tested. `gws` and the calendar config were absent on 2026-11-16 | [#268 brief, 2026-11-20](https://github.com/subculture-collective/subarchy/issues/268#issuecomment-7034389631) | Pending, Part 5 |
| Two-monitor reconnect (#98, M4) | Not tested. The panels were not connected at the readback after the 2026-11-16 reinstall | same | Pending, step 3.5 |

The row names follow the acceptance list on #51. Rows marked pending may
turn into passes or failures after the session; the final column then
changes, and failures get their own issues linked from #51.

### Results on earlier installations

These were observed on earlier installs of Subarchy on the same laptop
(2026-11-09 and 2026-11-14 to 2026-11-16, before the 2026-11-16 reinstall).
They are history, not results for core `0.0.0-638`
([[first-install#What the reinstall reset]]).

| Row | Result | Source |
|---|---|---|
| NVIDIA runtime power on battery under linux-lts `6.18.63-3-lts` | Passed: `suspended`, "Enabled (fine-grained)", video memory off, suspended time rising. Same driver and settings fail under Zen | [#195, 2026-11-15 03:42](https://github.com/subculture-collective/subarchy/issues/195#issuecomment-6888705161) |
| HT3 headphones: three noise modes, HT3-only volume, battery percentage | Owner confirmed | [#51, 2026-11-15 03:46](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6888745945) |
| Lid close and unlock, then standalone `systemctl suspend`, after the suspend fixes (Gitea PR #229 at the time; the suspend issue is GitHub #101) | Passed on core 438 and core 448. The first-install note records the standalone suspend; the 2026-11-09 comment records the lid cycle | [#51, 2026-11-09 23:54](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6782833850), [[first-install#Standalone suspend, November 9 evening]] |
| Dock with three monitors and lid closed | Layout applied and read back from the live compositor. Physical undock, cable swaps and reopen were not observed | [#51, 2026-11-16 17:15](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6923587683) |

## Untested ports (ADR 0050)

[[0050-hardware-support|ADR 0050]] ports Omarchy's x86_64 hardware fixes
for every vendor and area in its table, and says each port stays marked
untested until it runs on the matching machine. The 2026-11-08 progress
note says none had run on real hardware beyond what the VM exercises.

The Dell XPS 15 9520 above is the only machine that has run Subarchy. No
cited comment records which catalogue fixes `subcult hw fixes` lists on it.
Of the catalogue, one fix has a recorded read on it: the
`nvidia-runtime-pm` settings (`DynamicPowerManagement=2` and
`power/control=auto`) were loaded on core 607 on 2026-11-15
([#195, 2026-11-15 01:55](https://github.com/subculture-collective/subarchy/issues/195#issuecomment-6887593155))
and on core 638 on 2026-11-17
([#51, 2026-11-17 02:40](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6936334862)).
Loaded is not the same as working: the card still does not suspend on Zen
(see [[#Known limitations]]). No cited comment records a hardware result
for the other fixes, so they are untested:

- Apple (Intel and T2 Macs): `fix-t2`, SPI keyboard, NVMe suspend,
  `brcmfmac` supplicant.
- ASUS: ROG, ProArt P14 speakers, ExpertBook B9406, Z13 touchpad.
- Dell: XPS 13 speaker firmware and sidecar amplifiers, XPS touchpad
  haptics. The Dell power add-on (`dell-power`, a vendor add-on rather than
  a table entry) has owner results from the first install on 2026-11-09:
  the profile changed but the Dell label stayed stale until interaction,
  and the Dell permission unit worked at boot with charging thresholds
  50/85 ([#51, 2026-11-09 06:49](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6782833250),
  [23:54](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6782833850)).
  Not repeated on core 638.
- Framework: Framework 16 and QMK HID.
- Intel: Wi-Fi 7 EHT, FRED, IPU7 camera, LPMD, SOF firmware, thermald,
  video acceleration.
- Lenovo: Yoga Pro 7 bass speakers.
- Microsoft: Surface and Surface keyboard.
- Tuxedo: keyboard backlight.
- Peripherals: Elgato Cam Link 4K, Broadcom BCM43xx, Synaptics touchpad,
  function keys.
- General: NVIDIA modeset, Vulkan, speaker tuning, wireless regulatory
  domain.

ADR 0050 also lists fixes that are noted but not installed because their
packages are not in Arch's repositories (the IPU7 camera, qmk-hid, several
Dell and TUXEDO drivers, `v4l2-relayd`); see its 2026-11-08 progress notes.
The aarch64 fixes are not ported at all.

## Checked only in a VM

Secure Boot, TPM unlock and snapshot restore have run only in the VM
install test, never on Sputnik.

- Secure Boot and TPM: the 2026-11-08 VM run passed 78 checks "including
  snapshots and emulated Secure Boot/TPM"
  ([#51, 2026-11-08](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6782833085));
  [[0012-secure-boot|ADR 0012]] and [[0010-disk-encryption|ADR 0010]] say
  the VM test enables them. On Sputnik, Secure Boot is disabled and the
  LUKS volume has no token
  ([#51, 2026-11-16 21:07](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6929359466)).
  Checklist Q1 says key custody and the PCR policy are to be decided before
  a hardware test ([[test-checklist]]).
- Snapshot restore: `tools/iso/install-test.py` runs
  `limine-snapper-sync --restore` in the VM and checks the change made
  after the snapshot is gone (read in the repository on 2026-11-20, not
  rerun). Checklist R1, the same check on hardware, is unchecked, and the
  owner-session runbook says the restore is not run in the session
  ([#51, 2026-11-20](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-7033827474)).
  The runbook does boot a snapshot entry from Limine (step 4.6).
- The VM has no NVIDIA device, so none of the GPU results above come from
  it ([#195, 2026-11-16 15:13](https://github.com/subculture-collective/subarchy/issues/195#issuecomment-6920392864)).

## Known limitations

| Issue | What is wrong | Latest recorded state |
|---|---|---|
| #195 | On Zen `7.3.4-zen2-2-zen` with stock driver `620.70.06`, the NVIDIA card never reaches runtime D3 on battery: `runtime_status=active`, suspended time zero, "Runtime D3 status: Not supported". The awake card drew about 3.6 W in the 2026-11-14 report | Failed on battery on 2026-11-15 and again 2026-11-17 ([#195](https://github.com/subculture-collective/subarchy/issues/195#issuecomment-6936334494)). LTS passed on an earlier install, 2026-11-15, and is the tested workaround; not repeated on core 638. A source candidate for the upstream fix (NVIDIA PR #1512) built and booted in a VM, was not installed on Sputnik, and matches the current upstream head ([#195, 2026-11-20](https://github.com/subculture-collective/subarchy/issues/195#issuecomment-7033748537)). Whether #195 blocks the release is open (#285) |
| #249 | With every USB-C port empty and AC offline, the kernel's UCSI supply `USBC000:003` reads `online=1, Charging` and UPower reports `OnBattery=false`, so the power profile stays `balanced` | Seen 2026-11-17 02:28 on core 638. The 2026-11-20 diagnosis puts the fault at or below the kernel's UCSI connector state and proposes no code change; the cold-boot, post-suspend and reconnect controls have not been run ([#249, 2026-11-20](https://github.com/subculture-collective/subarchy/issues/249#issuecomment-7033753978)). On 2026-11-15, on an earlier install, all three UCSI supplies read offline after unplugging |
| #286 (L7) | A black screen of about 11 s before the disk passphrase prompt | Measured from boot logs on the 2026-11-14 reinstall: about 1.7 s of the 2.73 s before the prompt is NVIDIA module loading in the initrd; the rest falls in the 10 s loader phase. The gap itself has not been timed with a stopwatch, and the cause is not settled ([[first-install#Reinstall on November 14]], [[test-checklist]] F2). Open, with no fix |
| #89 | Google calendar sync is implemented (PR #215) and unconfirmed with a real account | Not attempted as of 2026-11-20 ([#268 brief](https://github.com/subculture-collective/subarchy/issues/268#issuecomment-7034389631)) |
| #98 | The two-monitor reconnect test (M4) is outstanding. Both ONN panels report the same serial `0x01010101`, so a saved layout follows the connector, not the panel | Not tested on core 638: the panels were not connected at the readback after the 2026-11-16 reinstall ([#268 brief](https://github.com/subculture-collective/subarchy/issues/268#issuecomment-7034389631)). Earlier that day, on the previous install, both panels ran in a dock layout and reported the shared serial; undock, replug and cable swaps were not observed ([#51, 2026-11-16 17:15](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6923587683)) |
| none | The installer removes the unsigned bootstrap package database, so `pacman` reports no `[subarchy]` database until the first sync fetches the signed one. `yay` and `tzupdate` are not in the default install | Observed 2026-11-16 ([#51, 20:38](https://github.com/subculture-collective/subarchy/issues/51#issuecomment-6928690350)); described there as consistent with the installer source, not as a defect |

Rows the owner deferred in the L5 ruling (#285) or the L6 ruling (#268):
**FILL AT TAG.** As of 2026-11-20 neither ruling is recorded. The decision
briefs on #285 and #268 are proposals and say nothing is decided
([#268, 2026-11-20 08:27](https://github.com/subculture-collective/subarchy/issues/268#issuecomment-7034389631)).
Failures found in the owner session are added here with their issue
numbers.

## Not in the first release

Each of these is described by an accepted decision or the site, and none is
built at `9e32591`. Whether each stays out of the first release is the
owner's call (#256, #272); this list states what was not found in the
repository on 2026-11-20.

| Missing | What the source says | Issue |
|---|---|---|
| User manual | ADR 0067 promises a Markdown manual under `docs/manual/`; the directory does not exist. The site has nine generated documentation pages under `site/docs/`; whether they count as the manual is open ([#257, 2026-11-20](https://github.com/subculture-collective/subarchy/issues/257#issuecomment-7034387179)) | #257, #277 |
| Backups | ADR 0060 chose restic backups; nothing is built ([#276, 2026-11-20](https://github.com/subculture-collective/subarchy/issues/276)) | #276 |
| Full keymap and cheat sheet | The system ships about 43 default bindings and no cheat sheet ([#292, 2026-11-20](https://github.com/subculture-collective/subarchy/issues/292)) | #292 |
| Printing | ADR 0022 accepts CUPS printing; nothing installs or enables it ([#294, 2026-11-20](https://github.com/subculture-collective/subarchy/issues/294)) | #294 |
| Factory reset | No command exists; checklist row R7 expects the `@factory` snapshot and says there is no command yet ([#262, 2026-11-20](https://github.com/subculture-collective/subarchy/issues/262)) | #262 |
| Same-disk install | Deferred beyond the first release: the installer wipes the whole selected disk. Only whole-disk encrypted installs are supported ([[guided-installer-scope]], [#250 decisions, 2026-11-20](https://github.com/subculture-collective/subarchy/issues/250)) | PR #233 |

## Verification of this note

- `/usr/bin/python3 tools/obsidian/check-vault.py`: result recorded in the
  pull request for #279.
- Not checked: that the sources still say what they said on 2026-11-20, and
  every **FILL AT TAG** field. Nothing here was run on Sputnik.

Related: [[first-install]] · [[test-checklist]] · [[0050-hardware-support|ADR 0050]] · [[0066-versioning|ADR 0066]] · [[review-index|Review index]]
