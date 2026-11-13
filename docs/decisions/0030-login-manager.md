---
title: "ADR 0030: Login manager"
type: decision
status: accepted
adr: 30
created: 2026-11-06
updated: 2026-11-13
tags: [decision, adr, session, brand]
aliases: [ADR 0030, L2, Login manager, SDDM]
---

# ADR 0030: Login manager

Decision map item L2. Accepted 2026-11-06.

## Decision

**SDDM** with a Subarchy **QML theme**. After the LUKS passphrase at boot,
the user logs in with their password, which also unlocks gnome-keyring
([[0023-authentication|ADR 0023]]).

## Options considered

| Option | Why not chosen |
|---|---|
| greetd with ReGreet or tuigreet | Lighter, but less theming reach. |
| Auto-login after disk unlock | One password per boot, but requires the login password to equal the disk passphrase and more PAM setup. Can be revisited as an opt-in. |

## Borrowed from Omarchy

`default/sddm/omarchy/` (`Main.qml`, `theme.conf`, images) as the structure
for the theme, and `default/sddm/hyprland.lua`, which runs the greeter under
Hyprland. Artwork and text are replaced (R4).

## Consequences

- The SDDM theme is QML, so it can share components and colours with the
  desktop shell if the shell is also QML (D1).
- Two password prompts per boot: disk, then login.
- SDDM must start the session through uwsm ([[0031-session-manager|ADR 0031]]).

## Progress

- 2026-11-07: SDDM runs its greeter inside Hyprland
  (`/usr/lib/sddm/sddm.conf.d/subarchy.conf`, compositor config
  `default/sddm/hyprland.lua`), as Omarchy does. The `SUBCULT` session
  (`/usr/share/wayland-sessions/subarchy.desktop`) starts Hyprland through
  uwsm (ADR 0031). The VM test sees the greeter on screen, then logs in with
  a test-only autologin and finds Hyprland under `wayland-wm@`. The greeter
  still uses SDDM's stock theme; the Subarchy QML theme is open.

- 2026-11-08: the greeter theme (issue #73): `default/sddm/theme/` is a
  small Qt 6 QML theme in the palette, the SUBCULT lockup over the last user
  and a passphrase field; Enter logs in, a failure says so and clears the
  field. Installed to `/usr/share/sddm/themes/subarchy` and selected by the
  package's `sddm.conf.d` file. The VM test's greeter screendump shows the
  ink background and the greeter log has no QML error.
- 2026-11-08: the user's palette (issue #103): `metadata.desktop` names
  `theme.conf`, which `subcult theme apply-system` writes beside `Main.qml`
  with the roles the greeter reads from `config` (base, surface, border,
  borderInactive, text, subtext, muted, error); without the file the
  shipped colours stand.
- 2026-11-12: the greeter's Hyprland runs with `HYPRLAND_NO_SD_TARGET=1`
  and `HYPRLAND_NO_SD_VARS=1`, so it no longer starts
  `hyprland-session.target` (and with it the bar, idle and clipboard
  services) for the sddm user; the desktop's user units also carry
  `ConditionUser=!@system`. The installer writes the new account as SDDM's
  last user, so the user field is filled before the first sign-in. A failed
  sign-in shows PAM's own text when there is some (a locked account says so
  and for how long), otherwise the general line.
- 2026-11-13: the greeter's layout follows the lock screen (issue #104):
  the lockup, the clock and the date in one centred column, then labelled
  User and Password fields in the lock's style (surface box, violet edge,
  green bullets, a padlock), a Sign in button, and `Subarchy · <host>`
  under them. Spacing and type grow with the logical screen size, from 1
  at 1280x800 to 2 at 3840x2160; below 640x600 the clock is left out.
  Two lines under the button stay free for a message, so the form does
  not move when one appears.
  The focused field's label turns bold. A running check shows "Checking…"
  in the field and "Signing in…" on the button. Return on the button signs
  in. Escape clears the password and the last message; in the user field
  it puts back the last user. A Caps Lock tag appears inside the password
  field: SDDM reports Caps Lock only under X11, so under Wayland the
  greeter infers it from the letters typed, and shows nothing until the
  first letter.
  `theme.conf` gains `accent` (the palette's green) for the bullets.
  `tools/test/greeter-test.sh` covers these and keeps previews at
  1280x800, 2560x1440 and 320x480.
- 2026-11-13: issue numbers here written before 2026-11-10 are Gitea
  numbers ([[vault-conventions#Links]]): #73 is Gitea #73 (GitHub #49) and
  #103 is Gitea #103 (GitHub #79). #104 is GitHub #104.

Related: [[decision-map|Decision map]] · [[0031-session-manager|ADR 0031]] · [[0013-boot-splash|ADR 0013]]
