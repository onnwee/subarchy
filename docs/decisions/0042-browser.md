---
title: "ADR 0042: Browser"
type: decision
status: accepted
adr: 42
created: 2026-11-06
updated: 2026-11-06
tags: [decision, adr, apps]
aliases: [ADR 0042, A4, Browser, Zen]
---

# ADR 0042: Browser

Decision map item A4. Accepted 2026-11-06.

## Decision

**Zen Browser** is the default browser. It is Firefox-based and is the
owner's default on `sputnik` (`x-scheme-handler/https=zen.desktop`).

**Chromium** is also preinstalled as a second browser (owner, 2026-11-06),
with extensions installed automatically:

| Kind | Mechanism | Needs network |
|---|---|---|
| Chrome Web Store extensions | Policy file in `/etc/chromium/policies/managed/` with `ExtensionSettings` (or `ExtensionInstallForcelist`), each entry's `installation_mode` set to `force_installed` (user cannot remove or disable) or `normal_installed` (installed automatically, user can disable) | Yes, downloaded on first launch |
| Subarchy's own extensions | Unpacked in the package and loaded with `--load-extension=` in `chromium-flags.conf` | No |

Which extensions, and whether they are locked, is open.

## Options considered

| Option | Why not chosen |
|---|---|
| Chromium (Omarchy) | Not the owner's browser. |
| Zen plus Chromium for web apps | Not chosen for now; see web apps below. |

## Consequences

- `zen-browser-bin` is not in Arch's repositories. On `sputnik` it comes from
  `[omarchy]`; Subarchy rebuilds it ([[0025-package-repository|ADR 0025]]).
- Zen needs a theme template (`userChrome.css` or Zen's theme settings) for
  [[0037-theming|ADR 0037]]; Omarchy's Chromium template does not apply.
- **Web apps** (A6): Omarchy runs them as Chromium `--app` windows. With Zen
  only, web apps need another mechanism, such as a Firefox PWA tool, or
  Chromium kept for web apps alone. Decide with the default app set.
- Browser policies (Omarchy's `install/config/browser-policy.sh`) are written
  for Chromium; Firefox-family policies use `policies.json`.
- Omarchy 4.5 already uses both extension routes: `/etc/chromium/policies/managed/omarchy.json`
  and `color.json` for policy, and `config/chromium-flags.conf` loading three
  bundled extensions from `default/chromium/extensions/` (Copy URL, a yt-dlp
  video download button with a native messaging host, and WhatsApp Slim).
  These are the starting point to borrow.
- Chromium (155 on `sputnik`) is a large package; it counts against the
  package budget ([[0054-lightweight-battery-first|ADR 0054]]).
- Chromium has phased out Manifest V2 extensions, so MV2-only extensions such
  as the original uBlock Origin may not run; uBlock Origin Lite is the MV3
  version. Check each extension's manifest version before listing it.

Related: [[decision-map|Decision map]] · [[0044-default-apps|ADR 0044]]
