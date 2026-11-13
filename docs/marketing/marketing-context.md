---
title: "Marketing context"
type: brand
status: draft
created: 2026-11-13
updated: 2026-11-13
tags: [brand, marketing]
aliases: [Marketing context, Positioning]
---

# Marketing context

What Subarchy is, who it is for and what it may claim. The
[[marketing-packet|marketing packet]] is written from this note. Everything
here is a draft: nothing is scheduled, sent or posted.

## What it is

An Arch Linux desktop distribution from SUBCULT. It runs Hyprland with its
own Quickshell shell, a separate lock screen and one palette, and is managed
through one command, `subcult`. It is built from scratch and borrows from
Omarchy where that fits.

## State, 2026-11-13

In development, with no release and no published image. The live ISO builds
in CI, boots in a virtual machine and installs into an encrypted virtual
disk. It runs on one laptop. Most hardware fixes are untested on real
machines, and several shell, launcher and theming items are open on the
[[roadmap]].

## Who it is for

- First, the owner, on his own machines ([[0054-lightweight-battery-first|ADR 0054]]).
- Then people who already run Arch or Omarchy, are comfortable building an
  ISO, and want a tiling desktop that is plain, quick and light on battery.
- Not yet: anyone who needs a download link, broad hardware support or a
  support channel.

## What sets it apart

| Point | Evidence |
|---|---|
| One command for the whole system | `subcult` finds every `subcult-*` program; `subcult commands` lists them |
| An update that can be undone | `subcult update` snapshots first; Limine has a boot entry per snapshot |
| A look that costs nothing to run | gaps 0, 1 px borders, no blur, shadow or animation ([[shell-and-look-design]]) |
| One palette in eight places | shell, lock screen, terminal, Neovim, cursor, SDDM, Plymouth, Limine |
| A lock screen that survives a shell crash | the lock is a separate program ([[0036-shell-components\|ADR 0036]]) |
| It says what is untested | the status table on the site and in the README |

## Claims

The supportable claims are C-SUBARCHY-01 to C-SUBARCHY-04 in the Product
Claims Register in `subcult-tv` (`studio/content/social/`), taken from the
README at `bb63709`.

Do not say or imply:

- that there is a release, a download or an install guide for real hardware;
- that it works on any machine other than the one laptop;
- that it is an Omarchy edition, fork or official variant;
- that it is Subcult OS, the event-operations product;
- "fast", "beautiful", "opinionated" or any benchmark.

## Voice

The person who maintains the machine, writing the changelog after the
update finished. It reads like release notes: what is installed, what was
tested and where, what was not. It names the command. The full voice section
is in `studio/content/VOICE.md` in `subcult-tv`.

## Brand

The owner chose the identity on 2026-11-13: the SUBARCHY wordmark in the
Bloody block font with highlights, in acid on ink; the SA_ mark with its
underscore under the A; Departure Mono for every word; the manual layout
with hairlines and figure captions. The pack is `studio/brands/subarchy` in
`subcult-tv`.

Related: [[marketing-packet|Marketing packet]] · [[brand-identity|Brand identity]] · [[0052-name-identity|ADR 0052]] · [[roadmap|Roadmap]]
