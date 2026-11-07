---
title: "ADR 0001: How Subarchy relates to Omarchy"
type: decision
status: accepted
adr: 1
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr]
aliases: [ADR 0001, Fork strategy]
---

# ADR 0001: How Subarchy relates to Omarchy

- Status: **accepted** 2026-11-06: option D, build from scratch
- Date: 2026-11-06
- Inputs: [[omarchy-overview|component map]],
  [[branding-surfaces|branding surfaces]],
  [[subcult-rice|SUBCULT rice]]

## Context

Subarchy should be a SUBCULT-branded desktop distribution. Three facts shape
the choice:

1. **Upstream moves fast.** Omarchy 4.5.0 ships 218 migrations dated
   2026-05-12 to 2026-11-02; 157 of them landed in the last 90 days. It also
   ships 556 commands, 32 shell plugins and hardware fixes for a dozen vendors.
2. **Branding is package-level.** The OS name, boot menu, boot splash, login
   screen and logos belong to `omarchy` and `omarchy-settings`, and
   `omarchy-settings` rewrites `/etc/os-release` and `plymouthd.conf` on every
   upgrade. A user-level overlay cannot rebrand them durably.
3. **The ecosystem depends on Omarchy's internal names.** All 39 community
   plugins and the 38 rice plugins run inside the Omarchy shell, call
   `omarchy-*` commands and read `~/.config/omarchy`. The existing rice is an
   overlay and needs a `post-update` hook to re-apply itself after updates.

## Options

| Option | What it means | Branding reach | Upstream cost | Plugin compatibility |
|---|---|---|---|---|
| A. Overlay (current rice) | Stock Omarchy plus Subarchy packages and user config | User-level only; boot, login and OS name stay Omarchy | Low, but re-applies after every update | Full |
| **B. Tracking fork, internal names kept** | Fork `omacom/omarchy`; change branding, defaults and package selection; keep `omarchy-*` commands, `~/.config/omarchy` and `$OMARCHY_PATH` | Full | Medium: regular merges of a small diff | Full |
| C. Hard fork with full rename | Rename commands, paths and packages to `subarchy` | Full | High: every upstream merge conflicts with the rename | Breaks community plugins until they are ported |
| **D. From scratch** | Own distribution assembled from upstream projects; each layer chosen in its own decision; Omarchy code borrowed where it fits | Full | No merges; borrowed code is copied and then owned | Only if a later decision keeps the Omarchy shell plugin API |

## Decision

Option **D**. Subarchy is its own distribution, built layer by layer from
the kernel up. Every layer gets its own decision record, listed in order in the
[[decision-map|decision map]].

Omarchy stays a source to borrow from, not an upstream to track:

- Omarchy's code is MIT-licensed. Copying a script, config, plugin or install
  step is allowed with the licence notice kept. Each decision record names what
  it borrows and from which Omarchy version.
- Borrowed code becomes Subarchy code. There is no merge from Omarchy; a later
  Omarchy fix is pulled in by hand when it is wanted.
- The Omarchy name, logos and artwork are not borrowed.

Option B (a tracking fork) was the earlier proposal. It was set aside because
the owner wants to choose every part, including those Omarchy fixes in place.

## Consequences

- Every layer needs a decision, an implementation and tests. That is far more
  work than a fork; the decision map makes the scope visible.
- No upstream merge burden. With 157 Omarchy migrations in 90 days, that is a
  real saving, paid for by maintaining everything Subarchy ships.
- Compatibility with the 39 community Omarchy plugins and the 38 rice plugins
  is no longer automatic. Whether Subarchy keeps the Omarchy shell plugin API
  is its own decision in the map.
- The SUBCULT rice, the inventory and the triage stay useful as a catalogue of
  parts to borrow or rebuild.
- Subarchy needs its own package repository, signing key, build pipeline,
  installer and update mechanism; each is a decision in the map.

Related: [[omarchy-overview|Omarchy component map]] · [[branding-surfaces|Branding surfaces]] · [[subcult-rice|SUBCULT rice]] · [[decision-map|Decision map]] · [[roadmap|Roadmap]]
