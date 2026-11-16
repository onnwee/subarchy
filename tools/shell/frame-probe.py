#!/usr/bin/env python3
"""Prepare a private shell copy that logs bar frames and clock ticks (#98).

Does not launch a shell, touch a service or change the source tree.
See docs/review/shell-display-findings.md for the measurement protocol.
"""

import argparse
import shutil
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[2] / "shell"
PROBE = '''import QtQuick
import qs.Commons

// Diagnostics only: no timer or scene item, and no production IPC handler.
QtObject {
  id: probe
  required property var window
  required property string output

  function record(event) {
    console.info("SUBCULT_FRAME_PROBE " + JSON.stringify({
      event: event, output: probe.output, at: Date.now(), clock: Clock.nowMs
    }))
  }

  readonly property Connections frames: Connections {
    target: probe.window
    function onFrameSwapped() { probe.record("frame") }
  }
  readonly property Connections clock: Connections {
    target: Clock
    function onNowChanged() { probe.record("clock") }
  }
}
'''
HOOK = '''
  // Test-only frame logging; this copy is never installed.
  FrameProbe {
    window: bar.contentItem.Window.window
    output: bar.screen ? bar.screen.name : ""
  }
'''


def prepare(source: Path, destination: Path) -> None:
    source, destination = source.resolve(), destination.resolve()
    if destination == source or source in destination.parents:
        raise ValueError("destination must be outside the source shell")
    bar = (source / "Bar.qml").read_text()
    if "id: bar" not in bar or not bar.rstrip().endswith("}"):
        raise ValueError("Bar.qml no longer has the expected bar root")
    # copytree refuses an existing destination, including another probe.
    shutil.copytree(source, destination)
    bar = bar.rstrip()[:-1] + HOOK + "}\n"
    (destination / "Bar.qml").write_text(bar.replace("import QtQuick\n", "import QtQuick\nimport QtQuick.Window\n", 1))
    (destination / "FrameProbe.qml").write_text(PROBE)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path, help="new directory for the instrumented shell")
    args = parser.parse_args()
    try:
        prepare(SOURCE, args.destination)
    except (OSError, ValueError) as error:
        parser.exit(1, f"frame-probe: {error}\n")
    print(f"frame-probe: prepared {args.destination.resolve()}; no process started")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
