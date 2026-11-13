# shell

Subarchy's desktop shell: a [Quickshell](https://quickshell.org) program in
QML ([ADR 0034](../docs/decisions/0034-shell-toolkit.md)), installed to
`/usr/share/subcult/shell/` and started by the user unit
`subcult-shell.service` with the graphical session. Design:
[shell and look design](../docs/plans/shell-and-look-design.md); widget
contract: [ADR 0068](../docs/decisions/0068-shell-plugin-api-v0.md).

| Path | Holds |
|---|---|
| `shell.qml` | Root: one bar and one background per output, notifications, OSD, polkit dialog, Alt-Tab, launcher, the `subcult.shell` IPC handler |
| `Commons/` | `Theme`, `Power`, `Config`, `Style`, `Clock`, `WidgetIndex`, `KeepAwake`, `Panels`, `Workspaces` and `Motion` singletons; the `WatchedFile` and `OverlayScreen` components; pure models (`*Model.js`); `Glyphs.js` and `HyprDispatch.js` |
| `Ui/` | `BarWidget`, `PanelBase` and `WidgetTimer` (the widget contract), `IconButton`, `Tooltip` |
| `PanelOverlay.qml` | The click-out panel host: one widget's `Panel.qml` at a time, under the widget on its bar's output; a click outside or Escape closes it |
| `widgets/<name>/` | One widget: `manifest.json`, `Widget.qml`, optional `Model.js`, `Panel.qml`, `tests/` |
| `widgets/auto-wallpaper/` | Off by default: rotates the wallpaper on the manifest's schedule (30 min on AC, 60 on battery, paused on battery unless `onBattery` is set); add `subcult.auto-wallpaper` to the bar layout to turn it on. `services/Wallpaper.qml` holds the schedule and the `subcult.wallpaper next` IPC call, so two full bars rotate once |
| `widgets/soma/` | SomaFM radio (plan 2): the panel fetches the channel list from somafm.com when it opens (at most every ten minutes), and so does `play <id>` before the list has loaded; a channel plays through mpv, and `services/Soma.qml` reads the song from mpv's JSON IPC socket as it changes, so now-playing is an event; nothing runs while stopped. `subcult.soma play <id>`, `stop`, `toggle` over IPC |
| `widgets/weather/` | Weather (plan 2): current conditions from Open-Meteo every 15 min on AC and 30 on battery; the forecast, sun, moon and tides from `linecast --json` (its own package) every 2 h on AC and 6 on battery, and when the panel opens with old data. Nothing is fetched until the panel sets a location (`linecast --search` behind the panel's box); `services/Weather.qml` holds the data for the widget and panel |
| `widgets/n8n/` | n8n (plan 2): active workflows and recent failed runs from the server's REST API, every minute on AC and five on battery; hidden until `server` is set (the panel's field); the API key comes from the keyring at every check (`secret-tool store --label='n8n API key' service subcult-n8n`) and reaches curl through a config on stdin, never a command line |
| `widgets/ht3/` | TOZO HT3 headphones (plan 2): in the bar only while an HT3 is connected over Bluetooth (BlueZ events, nothing polls). Opening its panel starts `subcult ht3 watch <address>` through `services/Ht3.qml`; the helper reads battery and noise mode over the headset's RFCOMM control channel (the protocol in `PROTOCOL.md` of the owner's omarchy-plugin-ht3), asks again every 30 s, and stops when the panel closes. A device counts as an HT3 when its alias or remote name contains both `HT3` and `TOZO`, as in the owner's plugin. Audio stays connected. The panel's Normal, ANC and Transparency buttons send the SET from `PROTOCOL.md` through the helper's stdin; the panel shows a mode only after the helper's GET readback reports it. Its volume bar moves only the HT3's own PipeWire output, chosen by the exact Bluetooth address in its node name, up to 100 %, and never changes the default output. No EQ (issue #153). `subcult ht3 status <address>` reads once from a terminal |
| `widgets/agents/` | Off by default: the coding agents' usage from `subcult agent usage --json` (Claude Code and Codex local files, no network), every 10 min on AC and 30 on battery while in the bar; tightest limit or tokens today in the bar, the rest in its panel; add `subcult.agents` to the bar layout |
| `widgets/battery/` | Battery charge, power profile and Dell charging controls in one panel. Choose **Battery: Icon / Icon and percentage** and **Power profile: Off / Icon / Icon and text** under **Bar display**; choices persist in the widget's `chargeDisplay` and `profileDisplay` settings. Dell firmware adds Quiet/Cool and charging modes, including Custom start/stop thresholds; other hardware uses power-profiles-daemon |
| `widgets/dell-power/` | Compatibility entry for the combined battery widget. Legacy layouts resolve this ID to `subcult.battery` without rewriting user files or showing both widgets. `subcult hw apply` now enables Battery on supported Dell machines; `services/DellPower.qml` retains the event-driven firmware state |
| `widgets/downloads/` | Off by default: yt-dlp downloads from the bar (paste a URL in its panel, or `subcult.downloads add <url>` over IPC); the widget stays in the bar when idle; `services/Downloads.qml` runs one at a time and nothing while idle |
| `widgets/tailscale/` | Tailscale ([ADR 0058](../docs/decisions/0058-tailscale.md)): `tailscale status --json` every minute on AC and five on battery, and when the panel opens; the panel turns it on and off, signs in (the link opens in the browser), lists the machines (a click copies the address, right click the DNS name), picks an exit node (the local network stays reachable) and sends files with Taildrop (`subcult tailscale send`, through the portal's file picker). Changes go through `pkexec /usr/lib/subcult/tailscale-helper` (polkit action `tv.subcult.tailscale`, no password in the active session; [ADR 0062](../docs/decisions/0062-privilege-policy.md)). Received files land in `~/Downloads` through the system unit `subcult-taildrop@<user>.service`. `services/Tailscale.qml` holds the state; `subcult.tailscale refresh`, `signIn`, `cancelSignIn`, `state` over IPC |
| `widgets/index.json` | Generated by `tools/shell/gen-index.py`; commit it after adding a widget |
| `services/` | Singletons shared by widgets and panels: `Notifications` (the notification daemon); `Alerts` (battery alerts, low 20 % and critical 10 % once per crossing with hysteresis from UPower events, and thermal alerts from `subcult thermal watch`); `Downloads`, `Soma`, `Weather`, `Wallpaper`, `DellPower`, `BluetoothPairing`, `MediaChoice` and `Ht3` (each behind its widget; `Wallpaper` also tells every output's background which image to show); `SettingsRunner` (the commands the settings panel's Apply runs, so closing the panel does not cut them off) |
| `tests/` | `qmltestrunner` tests for the models |

Nothing here is copied from Omarchy's shell or from community plugins; the
widgets reproduce the features of `sputnik`'s bar and are written for
Subarchy.

## Checks

```bash
make shell-test shell-lint shell-index-check
tools/test/shell-headless.sh shell   # the shell in a private headless sway
```

`shell-lint` fails on any qmllint warning. A few lines carry
`// qmllint disable …` for warnings only CI's qmllint gives on members that
both Quickshell builds declare.

## Running it

The session starts it; `systemctl --user restart subcult-shell` restarts it,
and `subcult update` restarts it after the `subarchy` package changed. The
unit turns Quickshell's file watcher off (a package upgrade would reload a
half-written tree) and its crash handler (systemd restarts on failure).
The unit is enabled for every user by a symlink in
`/usr/lib/systemd/user/graphical-session.target.wants/`, so a user turns it
off with `systemctl --user mask subcult-shell`, not `disable`.

Keys reach the shell as Hyprland global shortcuts with the appid `subcult`:
`default/hypr/bindings.lua` binds them with `hl.dsp.global("subcult:<name>")`
and Quickshell `GlobalShortcut` objects receive them, so a key press starts
no process. The names are `launcher-toggle`, `clipboard`, `alias.<name>`, `altswitch-next`,
`altswitch-prev`, `altswitch-commit`, `brightness-up`, `brightness-down` and `capslock`; `hyprctl dispatch
'hl.dsp.global("subcult:altswitch-next")'` sends one by hand.

IPC: `quickshell ipc -p /usr/share/subcult/shell show` lists the targets
(`subcult.shell status`, `subcult.osd flash <volume|brightness|capslock|workspace>`,
`subcult.altswitch next|prev|commit|cancel`,
`subcult.launcher open|close|toggle|clearHistory|search <query>|type <query>|enter|hotkey <alias>|state`).
Tests and scripts use it; the key bindings do not.

## Keep-awake

The indicators' keep-awake toggle holds a logind idle inhibitor
(`systemd-inhibit --what=idle --who=SUBCULT`), which hypridle honours under
any window. The state is `~/.local/state/subcult/keep-awake` (`1`, or
absent), so a shell restart keeps it; `subcult.shell keepAwake true|false`
sets it over IPC.

## Alerts

`shell/services/Alerts.qml` sends two kinds of notification, both event-driven.
Battery: low at 20 % and critical at 10 % while on battery, once per crossing,
re-armed five points above the threshold or by a charge (UPower property
changes). Temperature: a `hot` or `critical` trip point crossed, from the
kernel's thermal netlink events through `subcult thermal watch`, a process
that sleeps on the socket and prints one JSON line per crossing. A trip
alerts once per excursion (it must come back down first) and a zone keeps a
cooldown of 20 minutes (hot) or 5 minutes (critical). `subcult thermal zones`
lists the zones and trips a machine defines. The governor's `passive` and
`active` trips are ignored.

## Privacy marks

The indicators show, in the error colour, a microphone, a camera and a
screen mark while a client reads the microphone, a camera or the screen.
PipeWire tells: a device in use has a link from its node to the client's
stream, and device nodes carry type flags, so the microphone and camera
marks read links alone. Screen capture is a video stream linked from
anything but a camera (the screencast producer); video streams carry no
flags in Quickshell 0.3.2, so only the nodes that could be one are
tracked. A paused client still holds the device and keeps its mark; a
desktop-audio capture links from a sink and shows nothing. A recorder that
uses the compositor's capture protocol directly (wf-recorder over
wlr-screencopy) makes no PipeWire stream; Hyprland's `screencast` events
light the screen mark for it, from the first frames until half a second
after the last. The count is kept for the whole shell, so a bar added
later (a monitor plugged in, a reloaded widget) shows it too; a capture
already running when the shell starts is missed.
## Motion

One setting, `~/.config/subcult/motion.json` with `{"mode": "auto"}`, `"on"`
or `"off"`, decides whether the interface moves (the Motion group in the
settings panel). `auto` is on while on AC and off on battery. The shell's
`Motion` singleton (`Motion.enabled`, `Motion.duration`, 0 when off) follows
the file and UPower. When motion turns off it sends `hyprctl eval` with
only the gate (animations, blur and shadows off), so settings from the
user's own Hyprland config stay; when motion turns on it runs
`hyprctl reload`. The lock screen reads the same file.

## Calendar

The calendar widget shows the next event from the sync cache
`~/.local/state/subcult/calendar/events.json` (`subcult calendar sync`,
[ADR 0061](../docs/decisions/0061-default-bar-calendar.md)) and opens a
month panel: a dot marks days with events, a click lists that day. The file
is watched, so a sync changes the bar at once; the label follows the shared
minute clock. `subcult.shell widgetProperty subcult.calendar label` over
IPC returns the label (tests).

## Launcher

Super+Space opens it ([ADR 0057](../docs/decisions/0057-launcher.md)). An
empty query shows the favorites; typing searches desktop entries by name,
generic name, keywords and id, and the commands `subcult commands --json`
lists (read each time the launcher opens). Favorites come first in their own
order, then apps and commands by frecency, then by how well they match. Apps
start through `uwsm-app -- <id>.desktop`.

- Commands run in a terminal that stays open until Enter; one marked
  `silent` (`lock`, `system suspend`) has no output and starts without a
  terminal. A query that starts with a whole command passes the rest as its
  arguments (`font set Iosevka`). Commands marked `dangerous` ask first:
  Enter runs, Escape goes back.
- Calculator: `=` asks `qalc` alone; root search shows its answer for
  anything that looks like math (a digit with an operator, or `5 km to mi`).
  Enter copies the answer. Exchange rates are never fetched.
- Web: `@` lists the quicklinks, `@yt cats` searches one, `@anything` uses
  the default engine, and so does a query with no match. A quicklink keyword
  with words (`gh subarchy`) is offered first in root search too. URLs open
  with `xdg-open`.

- Files: `.` searches file and folder names under home with `fd` once typing
  pauses (case-insensitive, hidden and ignored files skipped, 60 results);
  nothing indexes in the background. Enter opens the pick with `xdg-open`.
- Emoji and symbols: `:` searches the names in unicode-emoji's
  `emoji-test.txt` (read the first time `:` is typed) and
  `/usr/share/subcult/default/launcher/symbols.json`; Enter copies the pick.
- Ask AI: the last row of a root search is "Ask <agent>", the default agent
  from `subcult app ask --json` (the `ask` command in the app catalogue,
  ADR 0047). The row says the text leaves the machine; Enter runs
  `subcult app ask -- <text>` and the answer shows in the preview pane,
  where Enter copies it. The launcher makes no other network use.
- Clipboard history: `$` and Super+Ctrl+V list what `subcult clipboard`
  keeps: text and PNG copies, newest first, 200 entries, under
  `~/.local/state/subcult/clipboard`. Typing after `$` filters; Enter puts
  the entry back on the clipboard; the last row clears the history. The
  watcher is `subcult-clipboard.service` (`wl-paste --watch`, which sleeps
  on the Wayland socket between copies; no timers). Copies marked
  `x-kde-passwordManagerHint` are never stored and are cleared from the
  clipboard after 30 s.
- Preview: the pane under the results shows the selected symbol, an image
  file, a folder's first entries, a text file's first lines, a clipboard
  entry or the agent's answer.
- Favorites: `/usr/share/subcult/default/launcher/favorites.json`, replaced
  by `~/.config/subcult/launcher/favorites.json` when that file has a
  `favorites` list of desktop entry ids.
- Script commands: executable files in `~/.config/subcult/commands/` with a
  `@raycast.title` (or `@subcult.title`) comment, read each time the
  launcher opens. Raycast's `mode`, `argument1`–`argument3` (`placeholder`,
  `optional`, `percentEncoded`), `description`, `packageName`,
  `needsConfirmation` and `currentDirectoryPath` keys work as in Raycast, so
  Raycast script commands run unchanged. `fullOutput` runs in a terminal,
  `compact` shows the last output line as a notification, `silent` shows
  nothing; `inline` runs as `compact` (no refresh timers). Missing arguments
  are asked for one at a time.
- Snippets: `/usr/share/subcult/default/launcher/snippets.json` and the
  user's `snippets.json` (`{"snippets": [{"name", "keyword", "text"}]}`).
  Enter fills `{date}`, `{time}` and `{clipboard}` and types the text into
  the focused window with `wtype`.
- Aliases: `~/.config/subcult/launcher/aliases.json`
  (`{"aliases": {"up": "subcult update", "hi": "script:greet.sh"}}`) names
  any item by its id: an app id, a command route, `script:<file>` or
  `snippet:<name>`. Typing the alias puts its item first, and words after
  it become arguments. Each alias is also the global shortcut
  `subcult:alias.<name>`; bind a key to it in `~/.config/hypr/hyprland.lua`
  with `sub.bind("SUPER + ALT + U", "Update", sub.alias("up"))`.
- Quicklinks: `/usr/share/subcult/default/launcher/quicklinks.json`
  (`default` engine, DuckDuckGo, plus `g`, `yt`, `gh`, `aur`, `wiki`, `aw`);
  `~/.config/subcult/launcher/quicklinks.json` adds or replaces links by
  keyword and may set `default`. A link is `{"name": …, "url": …}`; `{query}`
  in the URL makes it a search, otherwise the keyword alone opens it.
- History: `~/.local/state/subcult/launcher/history.json` (or under
  `$XDG_STATE_HOME`). Clear it with
  `quickshell ipc -p /usr/share/subcult/shell call subcult.launcher clearHistory`
  or by deleting the file.
- Quickshell keeps the app list and reloads it when desktop entries change;
  nothing polls.
