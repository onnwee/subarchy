---
title: "ADR 0042: Browser"
type: decision
status: accepted
adr: 42
created: 2026-11-06
updated: 2026-11-07
tags: [decision, adr, apps]
aliases: [ADR 0042, A4, Browser, Chromium]
---

# ADR 0042: Browser

Decision map item A4. Accepted 2026-11-06.

## Decision

**Chromium is the only browser** (owner, 2026-11-07). It is the default
browser, runs web apps in their own windows, and gets extensions installed
automatically.

Revised 2026-11-07: Zen was first the default, with Chromium as a second
browser; the owner dropped Zen.

Extension install routes:

| Kind | Mechanism | Needs network |
|---|---|---|
| Chrome Web Store extensions | Policy file in `/etc/chromium/policies/managed/` with `ExtensionSettings` (or `ExtensionInstallForcelist`), each entry's `installation_mode` set to `force_installed` (user cannot remove or disable) or `normal_installed` (installed automatically, user can disable) | Yes, downloaded on first launch |
| Subarchy's own extensions | Unpacked in the package and loaded with `--load-extension=` in `chromium-flags.conf` | No |

A third route, which Omarchy's `omarchy-install-chromium-claude` uses: a file
`/usr/share/chromium/extensions/<id>.json` containing
`{ "external_update_url": "https://clients2.google.com/service/update2/crx" }`
makes Chromium install the extension from the Web Store on next launch, and
the user can still remove it.

**Installed automatically** (owner, 2026-11-06), through that external
extension file so users can remove them:

| Extension | Publisher | Web Store ID | Notes |
|---|---|---|---|
| Claude ("Claude in Chrome") | Anthropic | `fcoeoabgfenejglbffodgkkbkcdhcgfn` | Works from a side panel; the listing says it needs a paid Claude plan. ID confirmed on the store page. |
| ChatGPT (OpenAI's Codex browser extension) | OpenAI | `hehggadaopoacecdllhhajmbjkdcmajg` | Lets the ChatGPT/Codex desktop app control the browser. OpenAI's Codex extension docs now redirect to this extension's page. Its docs list Chrome, Edge, Brave, Opera and Vivaldi, not Chromium, so it is untested here. |
| Bitwarden Password Manager | Bitwarden | `nngceckbapebfimnlniiiahkandclblb` | Owner, 2026-11-07; pairs with the preinstalled Bitwarden CLI |
| Vencord Web | Vendicated | `cbghhgpcnddeihccjmnadmkaejncjndb` | Owner, 2026-11-07; modifies Discord in the browser and in the Discord web app window |
| Proton Pass | Proton | `ghmbeldphafepmbegfdlkpapadhbakde` | Owner, 2026-11-07 ("everything from Proton") |
| Proton VPN | Proton | `jplgfhpmjnbigmhklmmbgecoobifkmpa` | Owner, 2026-11-07; browser-only proxy, separate from the system VPN app |

Further extensions are proposed from the owner's Vivaldi set and wait for
confirmation.

Use `force_installed` policy instead if they should ever be locked.

## Options considered

| Option | Why not chosen |
|---|---|
| Zen as default with Chromium beside it (first version) | The owner dropped Zen on 2026-11-07. |
| Vivaldi (the owner's other browser on `sputnik`) | Not chosen; its extensions are reviewed for Chromium instead. |

## Consequences

- Chromium's theme colour is set by managed policy, as Omarchy's
  `color.json` does; Theme Tender drives it ([[0037-theming|ADR 0037]]).
- **Web apps** run as Chromium `--app` windows with Omarchy's
  `omarchy-launch-webapp` approach. Extensions in the default profile also
  work inside web-app windows, so Vencord applies to the Discord web app.
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
