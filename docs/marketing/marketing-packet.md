---
title: "Marketing packet"
type: brand
status: draft
created: 2026-11-13
updated: 2026-11-13
tags: [brand, marketing]
aliases: [Marketing packet, Launch copy]
---

# Marketing packet

Drafts written from the [[marketing-context|marketing context]]. Nothing here
is approved for posting, and nothing is scheduled. Each line rests on a
claim in the Product Claims Register (`subcult-tv`), named in brackets.

## One line

An Arch Linux desktop from SUBCULT, run with one command. In development.
[C-SUBARCHY-01, 02]

## Short description (about 50 words)

Subarchy is an Arch Linux desktop distribution from SUBCULT. It runs
Hyprland with its own shell and lock screen, colours the whole system from
one palette, and is managed with one command, `subcult`. It is in
development: the ISO builds in CI and it runs on one laptop. There is no
release yet. [C-SUBARCHY-01, 02, 04]

## Long description

Subarchy is an Arch Linux desktop built from scratch by SUBCULT, borrowing
from Omarchy where that fits. You install it from a live ISO with a guided
installer that asks before it wipes anything. The installed system has an
encrypted btrfs root and a boot entry for every snapshot.

After that, `subcult` runs the system. `subcult update` takes a snapshot,
upgrades packages, runs migrations and cleans up. A new system follows a
dated Arch Linux Archive snapshot; `subcult channel set edge` follows the
Arch mirrors directly.

The desktop is Hyprland with Subarchy's own shell and a lock screen that is
a separate program, so a shell crash cannot unlock the session. One palette
colours the shell, lock screen, terminal, Neovim, cursor, login screen, boot
splash and boot menu.

It is not released. The ISO builds in CI, boots in a virtual machine and
installs into an encrypted virtual disk, and the system runs on one laptop.
Most hardware fixes are untested on real machines. [C-SUBARCHY-01 to 04]

## Site copy

The landing page and docs in `site/` use the lines above. The source file
behind each fact is listed in `site/README.md`.

## Status post (draft, not for posting yet)

> Subarchy is an Arch desktop we are building for our own machines.
>
> It runs on one laptop. That is the whole hardware list so far.
>
> `subcult update` takes a snapshot first, so a bad upgrade is one boot
> entry away from undone.
>
> No release yet. If you want to look, build the ISO and put it in a VM.
> subarchy.subcult.tv

The site answers at subarchy.subcult.tv since 2026-11-13, so the address
in this draft is real. The post itself is still not approved.
[C-SUBARCHY-02, 03]

## Demo brief

A 30 to 45 second screen recording, no narration, captions in Departure
Mono:

1. The installer's summary screen and the erase question, default no.
2. First login: the bar, a terminal, `subcult commands`.
3. `pult apply` changing the bar, window borders and terminal together.
4. `subcult update`, then the Limine menu showing the snapshot it made.

Record in a virtual machine with synthetic names. Show nothing that has not
been run. Label the recording "virtual machine".

## Release note template

Use when there is a first image. Until then there is nothing to announce.

> Subarchy <version>. Built from <commit>. Tested: <what, on which
> machines>. Not tested: <what>. Install: <link to the docs section>.

## First 30 days after a release

Not started; there is no release. When there is one: the site's install
section gets a download and checksum, the status post goes out once, the
demo is recorded, and issues are answered on GitHub. No paid promotion.

## Open

- The site is live at <https://subarchy.subcult.tv> (deployed 2026-11-13
  from `994d7fc`). A later change to `site/` needs a redeploy.
- No post has been drafted for a specific channel; use `social-craft` in
  `subcult-tv` for that.

Related: [[marketing-context|Marketing context]] · [[brand-identity|Brand identity]] · [[roadmap|Roadmap]]
