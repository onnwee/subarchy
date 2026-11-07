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

## Options considered

| Option | Why not chosen |
|---|---|
| Chromium (Omarchy) | Not the owner's browser. |
| Zen plus Chromium for web apps | Not chosen for now; see web apps below. |

## Consequences

- `zen-browser-bin` is not in Arch's repositories. On `sputnik` it comes from
  `[omarchy]`; Subcarchy rebuilds it ([[0025-package-repository|ADR 0025]]).
- Zen needs a theme template (`userChrome.css` or Zen's theme settings) for
  [[0037-theming|ADR 0037]]; Omarchy's Chromium template does not apply.
- **Web apps** (A6): Omarchy runs them as Chromium `--app` windows. With Zen
  only, web apps need another mechanism, such as a Firefox PWA tool, or
  Chromium kept for web apps alone. Decide with the default app set.
- Browser policies (Omarchy's `install/config/browser-policy.sh`) are written
  for Chromium; Firefox-family policies use `policies.json`.

Related: [[decision-map|Decision map]] · [[0044-default-apps|ADR 0044]]
