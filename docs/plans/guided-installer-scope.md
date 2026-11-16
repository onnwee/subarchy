---
title: "Guided installer: first-release scope and acceptance"
type: plan
status: active
created: 2026-11-16
updated: 2026-11-16
tags: [plan, installer, acceptance]
aliases: [Guided installer scope]
---

# Guided installer: first-release scope and acceptance

Reconciled on Kvant on 2026-11-16 against main `16475c8` for
[#124](https://github.com/subculture-collective/subarchy/issues/124) under
[roadmap #230](https://github.com/subculture-collective/subarchy/issues/230).
The original issue's description of plain prompts as the only interface
predates the merged guided installer. Its
[November 13 checklist](https://github.com/subculture-collective/subarchy/issues/124#issuecomment-6846137963)
already records most of the delivered work.

The owner explicitly delegated reasonable first-release scope decisions
for this reconciliation. Keep whole-disk installation with mandatory
encryption, defer same-disk alongside installation beyond the first
release, and retain the documented accessible boot menu and mark/bar
layout. This settles #124's product scope; it does not qualify a new ISO or
complete hardware acceptance on #51 or release sign-off on #84.

## Acceptance matrix

“Implemented” below means present in the inspected source with the named
checks. The dated observations below are separate evidence. None of these
rows claims a fresh VM or hardware run.

| Original item or retained behavior | First-release disposition | Current source and check or record |
|---|---|---|
| Starts itself on tty1 | Implemented | `iso/profile/airootfs/root/.zlogin`, tty1 autologin; `guided()` in `tools/iso/install-test.py` checks autostart (#125, #144). |
| Hidden boot menu | Settled deviation: visible for 2 seconds, with beep and speech entry | `iso/profile/efiboot/loader/loader.conf` and `02-subarchy-speech.conf`; #127 explains why hiding it would hide the speech choice. |
| Quiet boot | Implemented with visible startup progress | `01-subarchy.conf` keeps `loglevel=3`, with `console=tty0` last; #144 replaces the observed black-screen interval with status lines. `.zlogin` clears them before setup. |
| Themed console palette and Terminus font | Implemented | `prepareConsole`, `fitFont`, `fontFor` in `screens.go`; `TestFontFor`; guided VM harness checks font fit (#126, #128). |
| Centred mark, tagline, Return to start | Implemented | `greeter`, `drawLogo` in `screens.go`, embedded `logo.ans`; `TestScreensInstall`, `TestInstallViewLayout` (#126, #131). |
| Cleared screen per question, gum, Escape back | Implemented | `page`, `collectScreens`, gum helpers in `screens.go`; `TestScreensInstall`, `TestScreensEscape` (#126). |
| Language picker | Implemented for installed locale; installer text remains English | `language`, `languages` in `screens.go`; `TestScreensInstall` (#127). Translation of installer text was not part of this slice. |
| Labelled keyboard list | Implemented; layout loaded before secrets | `keyboard` in `screens.go`; `TestScreensInstall`, `TestKeyboardIsLoadedBeforeAnySecretIsTyped` (#126). |
| Searchable time zone list | Implemented with canonical zone names and substring matching | `zones`, `filter`, `account` in `screens.go`; `TestZones`, `TestScreensInstall` (#126, #142). |
| Network time zone guess | Implemented with bounded lookup and fallback | `timezone.go`: network, then language, then UTC; `TestLookupZone`, `TestHTTPGet`, `TestZoneGuess`, `TestPlainTimeZoneGuess` (#155). Real-network field check remains below. |
| Summary table, Yes / No, change it | Implemented; secrets hidden, erase question last | `summary`, `erase` in `screens.go`; `TestScreensInstall`, `TestScreensEscape` (#126, #129, #142). |
| Disk list with partition summary | Implemented, with optional read-only browse | `setup.Disks`, `disk`, `browse`; `TestDisks`, `TestDiskContentsAndBrowse`, `TestBeforeLook`, `TestLookPageAndCommand` (#125, #142, #143). |
| Internal disks first | Implemented; USB, FireWire and kernel-removable disks follow | `Disk.External`, `Disks` in `internal/setup`; `TestDisks` (#155). Mixed physical disk check remains below. |
| Install into free space beside another OS | Deferred beyond first release | Current `partition()` wipes the whole selected disk and creates its own ESP. Follow-up decisions below; no alongside option is offered. |
| Progress icon | Settled deviation: owner's mark above a bar | #131's requested layout, retained in `drawProgress`; `TestInstallViewLayout`. A stroke-by-stroke icon is not required. |
| Percentage and rotating tips instead of raw output | Implemented on virtual consoles; L toggles log | `progress.go`; `TestProgressOf`, `TestProgressMarkersMatchInstaller`, `TestInstallViewLogToggle`; `guided()` checks bar, package/hook counts, tip and log toggle (#127, #131, #142, #162). |
| Finish with duration, remove-medium advice and Reboot now | Implemented; staying in live system also possible | `finishedScreen`, `finished`; `TestScreensInstallEnd`, `TestFinishAndFailureScreens` (#125, #127, #142). Removal advice says to wait until restart. |
| Failure reason, current log tail, view-log/shell/reboot/power-off menu | Implemented | `failReason`, `failedScreen`, installer stderr handling; `TestFailReason`, `TestScreensInstallEnd`, `TestFinishAndFailureScreens` (#125, #127, #155). Warnings are excluded from fatal reasons. |
| One user/disk password or separate passphrase | Same password by default; separate passphrase offered | `account` and `collect`; `TestPasswordIsThePassphraseByDefault`, `TestScreensInstall` (#125). |
| Encryption may be switched off? | Settled: always LUKS2 | [[0010-disk-encryption\|ADR 0010]]; unconditional `encrypt()` in `subarchy-install`. |
| Overwrite confirmation style | Yes/No, default No, after summary | `erase`, `confirm`; `TestRunStopsWithoutConfirmation`, `TestScreensEscape` (#125, #129). |
| Works on serial console | Implemented as plain prompts, with raw install output | `onConsole`, `run`, `collect` in setup; `--plain` and `--batch`; `TestRunInstalls`, `TestRunStopsWithoutConfirmation`. VM harness also drives the serial shell. |
| Pre-wipe refusals | Present | `read_config`, `check_disk` before `partition()`; `tools/test/installer-check-test.sh` covers validation and active-volume checks. |
| 20 GiB minimum | Retained in offered setup targets | `setup.MinDiskBytes`, `Disks`; `TestDisks` excludes smaller disks. |
| Hardware detection | Retained | `hardware_list`, `subcult-hw` calls in `subarchy-install`; installer check script and existing VM hardware checks. |
| Online/offline package choice | Retained, including fallback from failed mirror install | `mirrors_reachable`, `pacman_conf`, `pacstrap_packages` in `subarchy-install`; `tools/test/installer-check-test.sh`; guided offline harness. |
| Root account locked | Retained | Source inspection: `configure_system` in `subarchy-install` calls `passwd --lock root`. No fresh installed-account observation was made here. |

The five proposed slices are accounted for: autostart/end/failure (#125),
screens/lists/summary/back (#126), progress (#127, #131, #142), themed boot
and console (#126–#128, #144), then language (#127) with same-disk alongside
explicitly deferred. The Wi-Fi page and live-network carry-over (#149)
remain delivered additions, covered by `network_test.go`.

## Why same-disk alongside installation is deferred

[[0009-disk-layout|ADR 0009]] assigns the entire target disk to a new
4 GiB ESP and LUKS2/btrfs root. [[0010-disk-encryption|ADR 0010]] requires
encryption. The implemented partition step uses `wipefs` and `sgdisk
--zap-all`; listing partitions or browsing them read-only does not make it
a partition-preserving installer. A new alongside choice would require a
different storage contract and could destroy the existing OS if built as
a small extension to the current step.

For the first release, another OS can remain on a **different disk** and
be selected in firmware. Automatic Limine chainloading of that disk's
bootloader is still absent, as recorded in `install/README.md`; it is not
evidence of same-disk support. The recorded Sputnik installation used a
separate disk.

Before any later alongside implementation, record an approved extension
or successor to ADR 0009 that decides:

1. Whether only already-unallocated space is supported or any partition
   resizing is allowed; the minimum contiguous free extent, including ESP
   space and encrypted root capacity. The current 20 GiB whole-disk picker
   threshold is not a free-space policy.
2. Whether to reuse an existing ESP or create another; required ESP size,
   file ownership, handling of insufficient space, and preservation of
   the existing OS's files, firmware entries and boot order.
3. Where the LUKS2/btrfs root goes, how target partitions are identified and
   confirmed, and how Limine discovers or chainloads the other OS.
4. Recovery and refusal behavior for unsupported layouts or interrupted
   installs, and a disposable pre-existing-OS fixture that proves its
   partition boundaries, data and boot path survive both success and
   refusal paths. Then qualify the chosen path on separately authorized
   hardware before advertising it.

No partition editor, disk operation or device change is authorized by
this reconciliation. The deferral settles release scope, not the future
layout decision, and does not add a blocker to #84.

## Qualification already recorded and still needed

- #127's [VM result](https://github.com/subculture-collective/subarchy/pull/127#issuecomment-6808023788)
  on November 11 records 86 passing checks at `e4db4ae`, including language.
- #131's [VM result](https://github.com/subculture-collective/subarchy/pull/131#issuecomment-6814086325)
  on November 12 records 88 passing checks at `8ec50ff` merged with #130,
  including the log window and font. It records screenshot review of the
  mark, centring and log layout.
- The [combined guided offline VM result](https://github.com/subculture-collective/subarchy/pull/144#issuecomment-6844013617)
  on November 13 records 108 passing checks at integration `a0572fc` for
  #142–#145 on main `1c305ff`. This predates #155.
- #155 merged on November 13 as `a41c936`. Its body and
  [review follow-up](https://github.com/subculture-collective/subarchy/pull/155#issuecomment-6846330763)
  record Go tests and installer/docs checks, not a new ISO/VM run. The
  failure reason is covered by Go tests; the successful guided VM harness
  does not deliberately fail an install. Its online mode can log a network
  zone guess, but the current CI wrapper runs `--guided --offline`, so a
  passing CI install does not prove a real geo-IP lookup.
- [[first-install#Artifact and recovery receipts|The first-install guide]]
  records the November 8 image, VM checks and separate-disk Sputnik
  installation. That image predates the guided-screen work above; it
  cannot qualify #155 or same-disk installation.

The three field checks from #124's November 13 comment remain unobserved
in this reconciliation. Carry them with the remaining hardware
qualification on [#51](https://github.com/subculture-collective/subarchy/issues/51):

- On a real network, confirm the time zone page's source note, offered
  guess and ability to select another zone. Service unavailability should
  still allow language/UTC fallback.
- With internal storage and a USB/removable disk present, confirm the disk
  list puts internal storage first. Inspect the list only; no install or
  erase is needed for this observation.
- After a separately authorized real installer failure, confirm the
  displayed reason and step match that run's error and tail, with no
  earlier-run lines. Do not cause a destructive failure just to collect
  this observation.

These field observations and exact-release-commit ISO qualification remain
distinct from #124's implementation and scope reconciliation. Release
evidence and owner sign-off stay under #84. No VM, ISO or hardware run was
performed for this documentation change.

Related: [[roadmap|Roadmap]] · [[0049-installer|ADR 0049]] · [[0009-disk-layout|ADR 0009]] · [[0010-disk-encryption|ADR 0010]] · [[first-install|First-install evidence]]
