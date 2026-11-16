---
title: "Shell and display finding acceptance"
type: review
status: active
review: pending
created: 2026-11-16
updated: 2026-11-16
tags: [review, testing, shell, display]
---

# Shell and display finding acceptance

Issue [#98](https://github.com/subculture-collective/subarchy/issues/98)
remains open under roadmap #230. Its November 15 wake-up regression, the
older rendered-frame question and physical monitor identity are separate
acceptance items. This review started from main `16475c8` on Kvant on
2026-11-16; no VM, ISO build or owner device was used for this review.

## Acceptance matrix

| Finding | Established evidence | What remains |
|---|---|---|
| Desktop Exec URL escaping | #98 records the fix in PR #205 | No open acceptance item in #98 |
| Basic auth for an iCalendar source | #98 records the fix in PR #203 | No open acceptance item in #98 |
| Sync repairs a corrupt calendar cache | #98 records the fix in PR #203 | No open acceptance item in #98 |
| DURATION before DTSTART | #98 records the fix in PR #203 | No open acceptance item in #98 |
| Webapp icon removal for all installed extensions | #98 records the fix in PR #205 | No open acceptance item in #98 |
| Invalid notification history elements | #98 records the fix in PR #206 | No open acceptance item in #98 |
| Headless inhibitor test isolation | #98 records the fix in PR #206 | No open acceptance item in #98 |
| Idle main-thread wake-ups | PR #217 merged as `54f8e6c`. The issue's run 22912 report records all 118 installed-system checks passing: 14 main-thread / 36 all-thread wake-ups in the quietest minute; limit remains 15 | No new wake-up failure established; retain the existing gate |
| Identical monitors across connector swaps | PR #227 merged as `60673b2`. Current tests pass for unique serials, connector swaps, empty/blank/duplicate/unmatched serial fallback and reservation before connector fallback. The added store/reload test checks mode, position, scale, rotation and workspaces when both connectors change and live enumeration reverses | M4 in [[test-checklist]]: re-save the profile and record the physical panels' reported serials and reconnect result. Blank or duplicate serials cannot identify the physical panel; this remains a documented limit, not a hardware pass |
| About five extra rendered frames per minute | Historical observation in #98; neither the passing wake-up gate nor PR #217 attributes those frames. A native headless control below recorded one clock notification and one frame in 60 seconds | Repeat in a controlled Hyprland guest, then attribute unexpected frames. The historical guest's frame count and widget cause remain unverified |

The first seven rows carry the issue's completed status; this review does
not claim a new hardware or account test for them. No remaining monitor
matching defect was reproduced in the focused software checks. PR #227
already implements the unique-serial case, so another matching change is
not justified by the existing evidence. Panels without distinguishable
identities still need an owner-recorded limitation or further requirements.

## Frame probe and decision

`tools/shell/frame-probe.py` prepares a new shell directory. It adds a
nonvisual `FrameProbe` to each bar and logs `QQuickWindow.frameSwapped`
and the shared clock's `nowChanged` signal with output name and epoch
milliseconds. It starts no process and changes no source file, widget
configuration, refresh interval, accessibility setting or budget.

A frame-swap signal is a Qt window rendering observation, not a measured
GPU presentation, a changed pixel count or a context-switch count. A clock
notification also does not imply that its label changed. Several swaps
near a clock tick must be counted separately rather than subtracted as
one presumed clock frame. Logging and profiling add work: do not use the
instrumented shell to qualify the wake-up budget.

The cached Arch environment has Quickshell 0.3.2 and can exercise these
hooks under headless sway. It lacks the original guest's Hyprland, system
and accessibility bus traffic and renderer. Its functional test deliberately
opens panels, changes outputs and sends notifications. Its frame count
cannot settle the earlier idle-VM observation. The QML profiler attach
command below was also checked with a small native offscreen application;
it produced a nonempty Qt trace and exited successfully. This validates
the collection mechanism, not frame attribution in Subarchy.

A separate native idle control on Kvant on 2026-11-16 retained the full
default widget layout, removed the functional harness's injected probe
widget from that layout, and sent no UI interactions. After 90 seconds of
warm-up, one complete 60-second interval on `HEADLESS-1` recorded **one
clock notification and one frame swap**, 2 ms apart. It used the cached
Quickshell 0.3.2 container, headless sway/pixman, Qt's software backend,
a two-CPU/1-GiB container limit, no network, the harness's private session
bus and helper fixtures, and no host system bus. No extra bar frame
reproduced in that interval. This short fixture control cannot clear the
original Hyprland/VM finding or establish its cause.

**Next integration probe belongs to the parent:** use a disposable overlay
of the retained installed VM, with no concurrent heavy job. No rebuild is
needed to investigate. Record the image/base revision, tested shell SHA,
kernel, Quickshell/Qt versions, renderer, CPU/RAM allocation, power source,
network state, output count, widget layout and running tray/media clients.
Keep the existing full layout and accessibility enabled. Use the previous
4-vCPU/4-GiB, network-off retained guest comparison where available; record
any difference. Do not run these service commands on the owner's desktop.

From the checked-out candidate root **inside that guest's graphical user
session**, first collect five whole minutes after a 90-second warm-up:

```bash
probe=$(mktemp -d /tmp/subarchy-frame-probe.XXXXXX)
python3 tools/shell/frame-probe.py "$probe/shell"
git rev-parse HEAD >"$probe/head"
systemctl --user is-active subcult-shell.service >"$probe/service-before" || true
restore_shell() {
  if grep -qx active "$probe/service-before"; then
    systemctl --user start subcult-shell.service
  fi
}
trap restore_shell EXIT
systemctl --user stop subcult-shell.service
systemd-inhibit --what=idle:sleep --mode=block \
  timeout --signal=INT 400s quickshell --no-color --log-times \
  -p "$probe/shell" >"$probe/frames.log" 2>&1
probe_status=$?
date +%s%3N >"$probe/finished-ms"
restore_shell
trap - EXIT
# A shell crash must not become five apparently quiet minutes.
if [ "$probe_status" -ne 124 ]; then
  printf 'Probe ended early (status %s); inspect frames.log.\n' "$probe_status" >&2
  exit 1
fi
printf '%s\n' "$probe"
```

Run the commands in a shell without `errexit`, so the expected timeout
does not skip the following collection steps. Do not interact with the
desktop during the recording. Summarize every interval, rather than choosing
the quietest frame minute:

```bash
python3 - "$probe/frames.log" "$probe/finished-ms" <<'PY'
import json
import sys
from collections import Counter
from pathlib import Path

events = []
for line in Path(sys.argv[1]).read_text().splitlines():
    if "SUBCULT_FRAME_PROBE " in line:
        payload = line.split("SUBCULT_FRAME_PROBE ", 1)[1]
        events.append(json.JSONDecoder().raw_decode(payload)[0])
if not events:
    raise SystemExit("No probe events: check shell startup before interpreting counts")
start = min(e["at"] for e in events) + 90_000
finished = int(Path(sys.argv[2]).read_text())
if finished < start + 300_000:
    raise SystemExit("Recording is too short for five complete minutes after warm-up")
counts = Counter((e["output"], (e["at"] - start) // 60_000, e["event"])
                 for e in events if start <= e["at"] < start + 300_000)
print("output minute clock_notifications frame_swaps")
for output in sorted({e["output"] for e in events}):
    for minute in range(5):
        print(output, minute + 1, counts[output, minute, "clock"], counts[output, minute, "frame"])
PY
```

If unexplained frames persist, collect binding evaluations, signal handlers,
JavaScript and scenegraph events in a **separate** recording. With the
normal shell stopped under the same restoration trap and the same private
copy, run:

```bash
trap restore_shell EXIT
systemctl --user stop subcult-shell.service
systemd-inhibit --what=idle:sleep --mode=block \
  timeout --signal=INT 400s quickshell --no-color --log-times \
  --debug 3768 --waitfordebug -p "$probe/shell" \
  >"$probe/profile.log" 2>&1 &
probe_pid=$!
trap 'kill "$probe_pid" 2>/dev/null; wait "$probe_pid" 2>/dev/null; restore_shell' EXIT
timeout 420s /usr/lib/qt6/bin/qmlprofiler --attach 127.0.0.1 --port 3768 \
  --include scenegraph,binding,handlingsignal,javascript,animations,painting,debugmessages \
  --output "$probe/frames.qtd"
wait "$probe_pid"
restore_shell
trap - EXIT
```

Keep that debug port inside the disposable guest. Inspect `frames.qtd` in
Qt Creator's QML Profiler: after the warm-up, correlate the probe's debug
messages and scenegraph frames with binding/signal source locations. A
nearby timer, helper or D-Bus wake-up alone is not widget attribution. If
the profiler cannot name the source, retain the trace and leave the finding
open; add a targeted signal trace for the candidate source before editing
its behavior. Do not disable widgets or accessibility to obtain a pass.

Close the frame item only after a repeatable cause has been identified and
either unnecessary redraws have a regression and measured fix, or expected
updates have documented evidence. If no excess reproduces, report all five
minutes and environment differences; do not call the historical cause
fixed. Run the unchanged wake-up gate on the uninstrumented candidate in
the parent's normal integration slot after any production change.

Related: [[test-checklist|Hardware acceptance]] · [[0054-lightweight-battery-first|Battery-first defaults]] · [[0068-shell-plugin-api-v0|Widget lifecycle]] · [[roadmap|Roadmap]]
