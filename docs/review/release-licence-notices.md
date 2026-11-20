---
title: "Release licence notice audit"
type: review
status: active
review: pending
created: 2026-11-16
updated: 2026-11-20
tags: [review, release, legal]
---

# Release licence notice audit

Observed on Kvant, 2026-11-16, against main
`702f9e0ac9a75e5fc57a5f71a566c954003ffb94`. This advances the existing
licence criterion in #84 under #230; it does not record release approval.
#241 tracks the focused notice repair.

## Checked package bytes

All 24 recipes (core plus 23 others) were inventoried. Their 27 non-debug
outputs were read from the qualified stable database: each downloaded or
retained archive matched its signed database SHA-256, detached signature,
package name and version. The archive inventory records notice paths and
hashes. No application was rebuilt or run locally for this audit.

Core `0.0.0-634` carries its GPL text, the retained Omarchy and rice notices,
and Departure Mono's OFL text. Its 16 Go executables were inspected with
`go version -m`; their three external modules match `go.mod`.
The core archive lacks the linked TOML and Go/BSD notices. This change
retains the pinned texts in `LICENSES/` and installs them with core.
The provenance table records their versions and hashes.

`tzupdate 3.1.0-1` carries no licence text. Its checksum-pinned source
archive contains Christopher Down's MIT notice. Release `3.1.0-2` installs
that unmodified file. Focused regressions invoke both real package functions
using build-output fixtures, inspect archives, and reject changed or
unreadable notices. The regular core archive test also compares the added
texts byte for byte. These local checks establish staging behavior; they
are not newly built signed-package evidence.

Pult's `0.4.1.r2.g7a703f1-1` archive carries its GPL, MIT and HuJSON BSD
texts. Both NVIDIA 580xx 32-bit packages carry independent vendor licence
files; the 64-bit OpenCL output has only a licence-directory link to
`nvidia-utils`, without a dependency that supplies it. This change replaces
that link with an independent vendor notice and bumps the 64-bit recipe
to `580.196.07-4`, distinct from lib32's `-3` registry filenames. All 32 cached Neovim plugin directories
carry licence files, alongside the starter licence and Subarchy NOTICE.
Presence alone does not establish all redistribution conditions.

## Current candidate, 2026-11-20

The audit above was written against main `702f9e0` and core `0.0.0-634`.
The candidate now under qualification is main `9e32591` with core
`0.0.0-638` (published to stable and edge in Gitea run 23109, 2026-11-16,
per the #84 comment). Main is held there until the tag ([[pending-decisions]],
#258). The licence gate is open as #261; the remaining notice checks are
#283. Nothing in this note was rechecked against `0.0.0-638`.

## Remaining limits

The final ISO bytes were not retained by the automatic run. The logs ZIP
is not the image. No image hash, filesystem notice coverage or final-image
licence pass is claimed here. After this fix is reviewed and the intended
source is settled, obtain the real image through one manual ISO workflow,
then record its hash, size, source, package versions and notice hashes.
Qualification of older main remains scoped to its original bytes.

Several other archives have no external package licence file, or retain
notices inside application resources. Those need their embedded notices,
shared system texts and corresponding-source paths reconciled against the
real image. The private matrix records each disposition; this repair does
not turn that unfinished work into a pass.

The existing asset provenance and owner rights assertion remain recorded
as supplied. They are not independent rights proof. The prior Claude
Commercial Terms acceptance in [[0053-licence|ADR 0053]] remains the recorded
owner decision. No new contract, permission, entitlement or legal clearance
is asserted. #84, #51 and #195 remain open; the owner decides release.

Related: [[0053-licence|ADR 0053]] · [[0066-versioning|ADR 0066]] · [[review-index|Review]]
