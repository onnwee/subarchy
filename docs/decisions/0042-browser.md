---
title: "ADR 0042: Browser"
type: decision
status: accepted
adr: 42
created: 2026-11-06
updated: 2026-11-07
tags: [decision, adr, apps]
aliases: [ADR 0042, A4, Browser, Zen, Chromium]
---

# ADR 0042: Browser

Decision map item A4. Accepted 2026-11-06.

## Decision

Revised 2026-11-07, third version: **Zen** is the default browser again, and
**Chromium** stays installed for web apps and for AI agents' browser control.
(History: Zen default with Chromium beside it on 2026-11-06; Chromium only
earlier on 2026-11-07; back to Zen once the owner recalled why they had
switched: Firefox still runs the full uBlock Origin, which Chrome-family
browsers lost with Manifest V2.)

| Browser | Role | Default | Package |
|---|---|---|---|
| **Zen** (Firefox-based) | Everyday browsing | yes | `zen-browser-bin` (AUR, rebuilt by Subarchy) |
| **Chromium** | Web-app windows (Discord), and the browser Claude and Codex control through their extensions | no | `chromium` (Arch `extra`) |

### Zen extensions

Installed through `policies.json` in Subarchy's Zen package
(`/opt/zen-browser-bin/distribution/policies.json`), with an
`ExtensionSettings` entry per add-on: `installation_mode: normal_installed`
and `install_url` pointing at the latest version on addons.mozilla.org. The
user can disable them but not remove them; switch an entry to `allowed` to
make it optional. Checked on addons.mozilla.org 2026-11-07:

| Add-on | Publisher | Add-on ID | AMO slug |
|---|---|---|---|
| uBlock Origin (full) | Raymond Hill | `uBlock0@raymondhill.net` | `ublock-origin` |
| SponsorBlock | Ajay | `sponsorBlocker@ajay.app` | `sponsorblock` |
| Bitwarden Password Manager | Bitwarden Inc. | `{446900e4-71c2-419f-a6a7-df9c091e268b}` | `bitwarden-password-manager` |
| Proton Pass | Proton | `78272b6fa58f4a1abaac99321d503a20@proton.me` | `proton-pass` |
| Proton VPN | Proton | `vpn@proton.ch` | `proton-vpn-firefox-extension` |
| Obsidian Web Clipper | Obsidian | `clipper@obsidian.md` | `web-clipper-obsidian` |
| Vimium | Phil Crosby | `{d7742d87-e61d-4b78-b8a1-b469842139fa}` | `vimium-ff` |
| Get cookies.txt LOCALLY | kairi | `{ac87cfd8-47b1-4401-b32e-f033af5ed96b}` | `get-cookies-txt-locally` |
| floccus | Marcel Klehr | `floccus@handmadeideas.org` | `floccus` |
| Tampermonkey | Jan Biniok | `firefox@tampermonkey.net` | `tampermonkey` |
| Enhancer for YouTube | Max RF | `enhancerforyoutube@maximerf.addons.mozilla.org` | `enhancer-for-youtube` |
| Reddit Enhancement Suite | honestbleeps et al. | `jid1-xUfzOsOFlzSOXg@jetpack` | `reddit-enhancement-suite` |
| HyperChat | Kento Nishi | `{14a15c41-13f4-498e-986c-7f00435c4d00}` | `hyperchat` |
| Karakeep | Mohamed Bassem | `addon@karakeep.app` | `karakeep` |
| Shodan | Shodan | `firefox-extension@shodan.io` | `shodan-addon` |
| Windowed | Michiel Dral | `{477dbe5e-1742-4641-a2c3-b6113bb5cf6e}` | `windowed` |
| Song Identifier (replaces Music Identifier) | losnappas | `song-id@losnappas` | `song-identifier` |
| SoundFixer (replaces Volume Master: per-tab gain, mono) | Val Packett | `soundfixer@unrelenting.technology` | `soundfixer` |

Threads Video Controls has no Firefox version and is dropped.

**Baseline: the owner's Zen profile on `sputnik`** (2026-11-07, profile
`9ysr1yvg.Default (release)`, 48 add-ons). Windowed, Song Identifier and
SoundFixer above come from it, and so do these, accepted by the owner
2026-11-07:

| Add-on | Publisher | Add-on ID | AMO slug |
|---|---|---|---|
| Firefox Multi-Account Containers | Mozilla | `@testpilot-containers` | `multi-account-containers` |
| SingleFile | gildas | `{531906d3-e22f-4a6c-a102-8057b88a1a63}` | `single-file` |
| Search by Image | Armin Sebastian | `{2e5ff8c8-32fe-46d0-9fc8-6b8986621f3c}` | `search_by_image` |
| Stylus | Stylus Team | `{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}` | `styl-us` |
| Control Panel for Twitter | Jonny Buchanan | `{5cce4ab5-3d47-41b9-af5e-8203eea05245}` | `control-panel-for-twitter` |
| PocketTube | Dima Nabok | `danabok16@gmail.com` | `youtube-subscription-groups` |
| Sink It for Reddit | SpecterAscendant | `{09acf9ff-55d4-4366-a1a9-c9b3c8877c09}` | `sink-it-for-reddit` |
| Better Videos for Instagram | Emir Kabal | `7f5862eb-3ab3-424c-aa6b-cf9311fba52f@emirkabal.com` | `better-videos-for-instagram` |

Not carried over from the profile: AdGuard, Ghostery, Privacy Badger,
DuckDuckGo Privacy Essentials and Decentraleyes (overlap uBlock Origin);
Greasemonkey (Tampermonkey chosen); Easy Youtube Video Downloader Express,
Instagram Downloader and Redditsave (yt-dlp covers them); Firefox
Translations, Read Aloud, Tranquility Reader and JSON Viewer Pro (Zen has
built-in translation, narration in Reader View, Reader View and a JSON
viewer); Remove Paywall; and the disabled Chatterino Native Host, Knockoff
and Wappalyzer.

**Zen mods** from the profile, seeded into new profiles on first run (mods
are not installable by policy): Floating History, Hide Extension Name, Pimp
your PiP, Better Find Bar, No pinned tab reset button, Better Unloaded Tabs,
Tab Text Size, Disable Rounded Corners, Better Tab Indicators, Tidy Popup,
SuperPins. Check each mod's licence before redistributing.

**Zen settings** from the profile, shipped as defaults through
`distribution/distribution.ini` (`[Preferences]`), since Firefox's
`Preferences` policy does not cover `zen.*` keys: tabs on the right
(`zen.tabs.vertical.right-side`), compact mode at startup
(`zen.view.compact.enable-at-startup`), workspace indicator at the bottom and
centred, continue where left off, Ctrl+Tab skips essential tabs, inactive
windows not greyed out.

### Chromium extensions

Installed with external extension files
(`/usr/share/chromium/extensions/<id>.json` with the Web Store update URL), as
Omarchy's `omarchy-install-chromium-claude` does; the user can remove them.

| Extension | Publisher | Web Store ID | Why in Chromium |
|---|---|---|---|
| Claude ("Claude in Chrome") | Anthropic | `fcoeoabgfenejglbffodgkkbkcdhcgfn` | Lets Claude control the browser with the user's sessions; paid Claude plan; no official Firefox version |
| ChatGPT (OpenAI's Codex browser extension) | OpenAI | `hehggadaopoacecdllhhajmbjkdcmajg` | Lets the ChatGPT/Codex desktop app control the browser; OpenAI lists Chrome, Edge, Brave, Opera and Vivaldi, not Chromium, so untested here |
| Vencord Web | Vendicated | `cbghhgpcnddeihccjmnadmkaejncjndb` | Applies inside the Discord web-app window |

Agent tools built on Playwright run their own browser without the user's
logins; these extensions are for agents working in the user's own
signed-in browser.

Other install routes kept on record: a managed policy in
`/etc/chromium/policies/managed/` (`ExtensionSettings`, `force_installed`
or `normal_installed`), and unpacked extensions loaded with
`--load-extension=` in `chromium-flags.conf`.

### Open

- None for extensions.

## Options considered

| Option | Why not chosen |
|---|---|
| Chromium only (second version) | Chrome-family browsers lost the full uBlock Origin; YouTube ads get through MV3 blockers. |
| Helium (ungoogled-chromium base, keeps Manifest V2, bundles full uBlock Origin) | Considered 2026-11-07; young project with MV2 support "as long as possible". The owner chose Zen. |
| Brave | Strong built-in blocker, but extra features to switch off; not chosen. |
| Vivaldi (the owner's other browser on `sputnik`) | Heaviest of the Chromium family; its extensions were reviewed instead. |

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
