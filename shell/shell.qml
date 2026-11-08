import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.services
import "Commons/LayoutModel.js" as LayoutModel

// Subarchy's shell (ADR 0034, shell and look design). One bar and one
// background per output; outputs that come and go get and lose theirs.
// Hyprland's FALLBACK output (shown when no monitor is connected) gets
// neither.
ShellRoot {
  id: shell

  readonly property var screens: Quickshell.screens.filter(s => LayoutModel.isReal(s.name))

  Variants {
    id: bars
    model: shell.screens
    delegate: Bar {}
  }

  Variants {
    model: shell.screens
    delegate: Background {}
  }

  NotificationPopups {}

  Osd {
    id: osd
  }

  PolkitDialog {}

  AltSwitch {}

  Launcher {
    id: launcher
  }

  // Battery alerts: a singleton with nothing to show; referenced here so
  // it exists for the session.
  readonly property bool alertsReady: Alerts.state !== null

  IpcHandler {
    target: "subcult.shell"

    // Used by the tests: keep-awake on or off.
    function keepAwake(on: bool): void {
      KeepAwake.enabled = on
    }

    // Used by the tests: which outputs have a bar, the power state, and the
    // interval each widget timer runs at right now.
    function status(): string {
      return JSON.stringify({
        bars: bars.instances.map(b => b.screen.name),
        widgets: Object.keys(WidgetIndex.widgets).length,
        loaded: bars.instances.reduce((acc, b) => { acc[b.screen.name] = (b as Bar).loadedIds(); return acc }, {}),
        shown: bars.instances.reduce((acc, b) => { acc[b.screen.name] = (b as Bar).shownIds(); return acc }, {}),
        keepAwake: KeepAwake.enabled,
        onBattery: Power.onBattery,
        popups: Notifications.popups.length,
        unread: Notifications.unread,
        history: Notifications.history.slice(0, 5).map(e => ({ id: e.id, summary: e.summary, body: e.body, appName: e.appName })),
        osd: osd.kind,
        launcher: launcher.open,
        intervals: Power.report()
      })
    }
  }
}
