---
title: "Pending decisions"
type: review
status: active
review: pending
created: 2026-11-20
updated: 2026-11-20
tags: [review, release, decision]
aliases: [Open owner decisions]
---

# Pending decisions

Every owner decision still open on 2026-11-20, listed once, with the issue
that holds it and a stated default. The tracker is
[roadmap #250](https://github.com/subculture-collective/subarchy/issues/250).
Nothing below is decided. A default is an agent's suggestion from the
decision briefs and correction comments posted on each issue on 2026-11-20;
answer on the issue in one line, for example "all defaults, but a2".

This replaces [[next-decisions]] (frozen 2026-11-07) as the place to start.
Checklist IDs (Q1 to Q25) stay as they are in [[test-checklist]] section 13,
which keeps the wording and the settled list. The briefs quote the files and
numbers they cite; the facts there are the briefs' own readings, so check
the issue before relying on one.

Order of answering: #268 before the owner session (#275) because it can add
Secure Boot steps; #285 after that session, because it needs its readings;
#265 before #271 and #272, which wait on it.

## Release and channel

| Issue | Decision | Options | Default |
|---|---|---|---|
| [#259](https://github.com/subculture-collective/subarchy/issues/259) | **a.** Where the 7.10 GB ISO is served from (GitHub allows 2 GiB per release file) | homelab static host, object storage (R2), torrent, split parts, shrink | **Object storage (a2).** The first brief suggested the homelab host (a1); the correction found that Cloudflare's terms point large files to its paid storage unless the account is Enterprise. Keep a1 only if the download host stays outside Cloudflare's proxy. `SHA256SUMS` and its signature stay on the GitHub release either way. |
| #259 | **b.** File name | rename the retained bytes to `subarchy-0.0.0-x86_64.iso`; keep the date name; rebuild | Rename (b1); the bytes and hash do not change. |
| #259 | **c.** What is signed | detached signature on `SHA256SUMS`; also the ISO; nothing | Sign `SHA256SUMS` (c1). |
| #259 | **d.** Who signs, where the public key lives | owner by hand on `soyuz`; key in CI | By hand on `soyuz` (d1); public key on the site, the release and the repository, fingerprint in the release notes. Answer #263 first. |
| [#260](https://github.com/subculture-collective/subarchy/issues/260) | **a.** What stable follows after the tag | main; tags only; lag edge by a tested interval | **Lag (a3)**, the least new machinery and the only option consistent with Arch packages still moving. The brief suggested tags only (a2) with an early snapshot advance (d1); the correction found those two conflict as built, and tags only needs one of three snapshot-delivery choices (s1 to s3). |
| #260 | **b.** Is an untested intermediate commit acceptable on stable | yes / no | No (b1): a build reaches stable only if the ISO build and install test passed on that exact commit. |
| #260 | **c.** Does edge keep every main commit | yes / no | Yes (c1). |
| #260 | **d.** How Arch security fixes reach stable between releases | early snapshot advance; only with a release | Follows a: with a3 the existing weekly advance carries them; with tags only, see s1 to s3. |
| [#265](https://github.com/subculture-collective/subarchy/issues/265) | **a.** Who Subarchy is for after 0.0.0 | owner first; invite outside users | Owner first, public source, no support promise (a1); revisit after a month without a serious fault. |
| #265 | **b.** Release cadence | none; patch on need and minor about monthly; a release per weekly snapshot advance | Patch when a fix is needed, minor about monthly while 0.x (b2); a new ISO on minor releases only. |
| #265 | **c.** What a version number promises | nothing while 0.x; stricter | While 0.x no compatibility promise; migrations carry installed systems (c1). |
| #265 | **d.** Support surface | issues only; Discussions; security contact | Issues only plus a `SECURITY.md` contact (d1 + d3). |
| [#268](https://github.com/subculture-collective/subarchy/issues/268) | **a.** May #51 close with rows recorded as not tested | attempted rows only; never; any row | Attempted rows only, each with a dated reason, listed in the release notes (a1). |
| #268 | **b.** Secure Boot and TPM unlock on hardware (checklist **Q1**: key custody, firmware recovery, PCR policy) | defer past the tag; require before it | Defer (b1): opt-in feature, VM test covers the mechanism. If required, answer Q1 here first. |
| #268 | **c.** Is #89 (Google sync) required | required; attempt, ship with CalDAV and iCal if it fails; skip | Attempt, not required (c2). |
| #268 | **d.** #98's two remaining items | close frame finding as not reproducible, keep M4 as attempt; keep both open; close both | First (d1). |
| [#285](https://github.com/subculture-collective/subarchy/issues/285) | **a.** NVIDIA runtime power on hybrid laptops (#195) | Zen default with LTS as workaround; LTS on hybrid only; LTS everywhere | Zen default, documented limitation (a1), subject to the session's LTS reading. Ask after #275. |
| #285 | **b.** Is #249 (false charging) release-blocking | yes / no | No (b2), unless the session shows otherwise. |
| #285 | **c.** If session results are mixed | rule on what was measured; hold | Rule on what was measured (c1). |
| #285 | **d.** Where the ruling is recorded | | On #195, #249, #84, the release notes, and dated notes on ADR 0004 and 0054. |
| [#269](https://github.com/subculture-collective/subarchy/issues/269) | **a.** Serial-console root login on public images | keep for 0.0.0; remove; separate serial entry; kernel parameter | Keep for 0.0.0 (a1); for the next image prefer a separate serial boot entry (a3), because the parameter variant (a4) still leaves a root shell unless it also removes the serial getty. |
| #269 | **b.** Where it is recorded | ADR 0063; ADR 0049 | ADR 0063 plus one release-notes line (b1). |

## Licence and rights (checklist Q20, Q21)

| Issue | Decision | Default |
|---|---|---|
| [#261](https://github.com/subculture-collective/subarchy/issues/261) | **a.** Does the licence gate pass now that the repository is public (since 2026-11-13, [[0053-licence\|ADR 0053]]) | Pass for the tag after named checks finish: the notice matrix (#283), installed-system notice readback, the DisplayLink and NVIDIA 580xx rulings, and the asset statement (a2). |
| #261 | **b.** DisplayLink redistribution | No default: the repository records no reading of the terms. |
| #261 | **b'.** NVIDIA 580xx redistribution (added by the correction comment) | No default, for the same reason. |
| #261 | **c.** SUBCULT marks and artwork | Dated owner statement on ADR 0053 now (c1); written terms for forks after the release (c2). |
| #261 | **d.** Origin headers on borrowed files | Sweep folded into #283 (d2); if gaps appear, a new candidate or a known limit. |
| [#84](https://github.com/subculture-collective/subarchy/issues/84) | **Q21.** Review the tested-hardware list in the release notes and tag the first release | Decide after #261, #268 and #285 are answered. |

## Small decisions from the checklist

All in [#256](https://github.com/subculture-collective/subarchy/issues/256)
(brief and correction of 2026-11-20). Q1, Q19, Q20, Q21 and Q22 have their
own issues and are not repeated here.

| ID | Decision | Default |
|---|---|---|
| Q2 | Keep or drop Omarchy's "Limine" firmware entry | Keep. |
| Q3 | Online installs stay on the stable snapshot | Yes. |
| Q4a | Installer offers read-only LUKS unlock while browsing | Leave out for now. |
| Q4b | Keep the visible 2 s boot menu with a beep (added by the correction) | Keep. |
| Q5 | Faint focused button or progress track | No change until the owner session judges I13 and I14. |
| Q6 | 1.5 s black before shutdown splash; hide its progress bar; sign past 16 password characters | Accept the gap (listed under #286); keep the bar; add the sign as a small issue. |
| Q8 | Tailscale without a password; the list of actions that skip sudo or polkit | Confirm both as in [[0062-privilege-policy\|ADR 0062]]. |
| Q9 | voxtype dictation | Bind Alt+Space, start on first use. |
| Q10 | Default apps file; six missing "preinstalled" apps; CUPS; package budget | Ship `/etc/xdg/mimeapps.list`; unmark the six; add CUPS after the release (#294); keep the budget and raise it in the PR that adds a package. |
| Q11 | Finish the app list review | After the release. |
| Q12 | Kitty cursor colour | Keep #FFFFFF and the Subcult Ink scheme. |
| Q14 | 25 upscaled wallpapers; the other 84 | Approve the 25; leave the 84 out for now. |
| Q15 | SUBCULT mark or Subarchy identity on installer, boot, greeter, lock; vendor URLs | Keep what the candidate has; site for user-facing URLs, repository for PKGBUILD `url=`. |
| Q16 | restic target | Dozor over SFTP (a homelab change; #276 waits on it). |
| Q18 | Factory reset with a keep-home mode | Build both. |
| Q25 | Captive-portal sign-in in the first release | No; list as a known limit. |
| ufw | Does ufw need a `tailscale0` rule | Test first, then decide. |
| HT3 EQ | The EQ control left from Q7 | Defer. |

Q19 (second copy of the signing key) is open on
[#263](https://github.com/subculture-collective/subarchy/issues/263); the
draft procedure is [[key-rotation]]. Q22 (black gap before the Plymouth
prompt) is tracked in #286. Q1 is part of #268 b.

## After the first release

| Issue | Decision | Default |
|---|---|---|
| [#270](https://github.com/subculture-collective/subarchy/issues/270) | Which of the 47 unbuilt `subcult` commands to keep (see [[cli-command-set]]) | Keep 35, cut or defer 12: drop `capture qr`, `toggle suspend`, `network band`, the `pkg` group, `reminder`, `transcode`, `setup timezone` and `language` as commands; defer `system hibernation` and `setup input`. Order: `version` and `system kernel` first, then smallest groups first. |
| [#271](https://github.com/subculture-collective/subarchy/issues/271) | **a.** How untested hardware fixes ship | Enabled and labelled (a2), or a release-notes table only if #265 is "owner first". |
| #271 | **b.** A published tested and untested table | Generated from `internal/hw/fixes.go` (b1). |
| #271 | **c.** A second test machine | Decide after the first release (c3). |
| [#272](https://github.com/subculture-collective/subarchy/issues/272) | Larger features: same-disk install beside another OS; plugin API v1; desktop-control server ([[0059-agent-desktop-control|ADR 0059]]); translation; accessibility pass; other CPU architectures; following Omarchy changes | Defer same-disk install and look again after two releases; defer the full plugin API; defer the desktop-control server one quarter and recheck vendors; drop translation for now; accessibility audit at the first minor release; drop other architectures; re-inventory Omarchy by hand at each minor release (g2). |

## Not in this note

Settled items are in [[test-checklist]] section 13 with their evidence. The
KVM runner notes in [[ci-runner]] are corrected under #299, not here.
