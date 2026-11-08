import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.services

// Subarchy's shell (ADR 0034, shell and look design). One bar and one
// background per output; outputs that come and go get and lose theirs.
ShellRoot {
  id: shell

  Variants {
    id: bars
    model: Quickshell.screens
    delegate: Bar {}
  }

  Variants {
    model: Quickshell.screens
    delegate: Background {}
  }

  // Keep-awake (the indicators' toggle) for the whole session, held by the
  // first bar's window.
  IdleInhibitor {
    window: bars.instances.length > 0 ? bars.instances[0] : null
    enabled: KeepAwake.enabled
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

  IpcHandler {
    target: "subcult.shell"

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
