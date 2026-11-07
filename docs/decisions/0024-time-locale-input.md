---
title: "ADR 0024: Time zone, locale and input methods"
type: decision
status: accepted
adr: 24
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, system, i18n]
aliases: [ADR 0024, S10, Time zone, Input methods]
---

# ADR 0024: Time zone, locale and input methods

Decision map item S10. Accepted 2026-11-06.

## Decision

- **Automatic time zone**: the system time zone follows the machine's
  location, so travel needs no action. The user can pin a zone to turn this
  off.
- **Input methods on demand**: fcitx5 and its Chinese, Japanese and Korean
  engines install only when the user adds a language that needs them.
- Locale and keyboard layout are chosen at install.
- Time sync uses `systemd-timesyncd`.

## Options considered

| Option | Why not chosen |
|---|---|
| fcitx5 on every install (Omarchy) | More packages and a background daemon for users who type only Latin scripts. |
| Manual time zone | No geo-IP lookups, but travel needs a manual change. |

## Borrowed from Omarchy

- `tzupdate` (geo-IP time zone lookup) and Omarchy's sudoers rule that lets it
  set the zone without a password.
- `install/user/input-method.sh` and `default/input-methods/` for the on-demand
  install.

## Consequences

- Omarchy installs `tzupdate` but this inventory did not find what triggers it
  automatically. Subarchy needs a trigger, such as a NetworkManager
  dispatcher on connect, or an alternative like `automatic-timezoned` with
  geoclue. Decide when implementing.
- A geo-IP lookup sends the machine's public IP address to the lookup
  service on each trigger.

Related: [[decision-map|Decision map]] · [[0016-networking|ADR 0016]]
