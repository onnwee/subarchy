---
title: "ADR 0013: Boot splash"
type: decision
status: accepted
adr: 13
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, boot, brand]
aliases: [ADR 0013, B7, Boot splash]
---

# ADR 0013: Boot splash

Decision map item B7. Accepted 2026-11-06.

## Decision

**Plymouth** shows a themed splash from the initramfs to the login screen,
and draws the LUKS passphrase prompt.

## Options considered

| Option | Why not chosen |
|---|---|
| No splash, quiet console | Less to build, but the boot looks unfinished. |

## Borrowed from Omarchy

The Plymouth theme structure in `default/plymouth/` (`omarchy.plymouth`,
`omarchy.script`, progress bar, bullet and lock images) and
`omarchy plymouth set`, which recolours the splash from the active theme. All
artwork is replaced with Subarchy marks (R4); the Omarchy logo is not
borrowed.

## Consequences

- The `plymouth` hook sits in the systemd initramfs line
  ([[0008-initramfs|ADR 0008]]).
- Plymouth's own config must not be overwritten on update the way
  `omarchy-settings` resets `/etc/plymouth/plymouthd.conf`; Subarchy owns the
  file through its package instead.
- Needs SUBCULT splash artwork: logo, progress elements, unlock prompt.

## Progress

- 2026-11-07: the installer adds the `plymouth` initramfs hook and `quiet
  splash`; in the VM test Plymouth starts and takes the LUKS passphrase. The
  test boots with `console=ttyS0`, which puts Plymouth in text mode, so the
  graphical splash itself is untested. The theme is Arch's default until the
  Subarchy theme exists.
- 2026-11-08: the Subarchy theme (issue #73): `default/plymouth/` holds
  `subarchy.plymouth`, an own `subarchy.script` (ink background, the
  SUBCULT mark, a violet track filling with acid green, the passphrase
  prompt with a lock and bullets, messages in paper) and the SVG sources of
  the small images; the package renders them with rsvg-convert and installs
  the theme. The installer writes `/etc/plymouth/plymouthd.conf` before
  pacstrap, so the UKIs built during it carry the theme (pacman keeps the
  file and writes its own as `.pacnew`). The VM test checks the theme is
  selected and installed; the splash is still drawn in text mode there.
- 2026-11-08: the user's palette (issue #103): `subcult theme apply-system`
  writes a recoloured copy of the theme to
  `/usr/share/plymouth/themes/subarchy-user` (background and message text
  from the palette; the images linked from the packaged theme), selects it
  in `plymouthd.conf` and rebuilds the initramfs, only when those changed.
- 2026-11-12: the prompt has a "Disk passphrase" label above the field, and
  after a wrong passphrase it says "That passphrase didn't work. Try again."
  under it. systemd-cryptsetup sends no failure message, so the script reads
  a second ask with the same prompt as a failed one. The installer adds
  `tries=0` to `rd.luks.options`, so the prompt asks again without limit:
  the default of three ended in the initrd's emergency shell, which the
  locked root account cannot open. Migration `1794532900` adds it to
  earlier installs and rebuilds their UKIs. A splash recoloured earlier is
  a copy made by `subcult theme apply-system` and keeps the old prompt
  until that runs again; the migration says so when `subarchy-user` is
  selected.

Related: [[decision-map|Decision map]] · [[0008-initramfs|ADR 0008]] · [[brand-identity|Brand identity]]
