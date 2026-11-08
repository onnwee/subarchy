import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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
        osd: osd.kind,
        launcher: launcher.open,
        intervals: Power.report()
      })
    }
  }
}
