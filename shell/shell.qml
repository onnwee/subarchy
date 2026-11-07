import QtQuick
import Quickshell
import Quickshell.Io
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

  NotificationPopups {}

  Osd {
    id: osd
  }

  PolkitDialog {}

  IpcHandler {
    target: "subcult.shell"

    // Used by the tests: which outputs have a bar, the power state, and the
    // interval each widget timer runs at right now.
    function status(): string {
      return JSON.stringify({
        bars: bars.instances.map(b => b.screen.name),
        widgets: Object.keys(WidgetIndex.widgets).length,
        loaded: bars.instances.reduce((acc, b) => { acc[b.screen.name] = (b as Bar).loadedIds(); return acc }, {}),
        onBattery: Power.onBattery,
        popups: Notifications.popups.length,
        unread: Notifications.unread,
        osd: osd.kind,
        intervals: Power.report()
      })
    }
  }
}
