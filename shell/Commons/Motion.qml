pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "MotionModel.js" as Model

// Whether the interface moves (rice port; ADR 0054): the motion setting
// combined with the power source. Widgets read `enabled` or `duration`
// (0 when motion is off). When the answer changes, the compositor is told:
// off sends the gate alone through `hyprctl eval`, on is a `hyprctl reload`
// (see MotionModel.js). Driven by the file watch and UPower; nothing polls.
Singleton {
  id: root

  readonly property string mode: Model.mode(file.text)
  readonly property bool enabled: Model.enabled(mode, Power.onBattery)
  readonly property int duration: enabled ? 160 : 0
  property bool pending: false

  onEnabledChanged: root.apply()

  function apply() {
    if (hyprctl.running) {
      root.pending = true
      return
    }
    // Set here, not bound: a binding may not have caught up with `enabled`
    // when this handler runs, and the old command would be sent.
    hyprctl.command = Model.command(root.enabled)
    hyprctl.running = true
  }

  Process {
    id: hyprctl
    onExited: {
      if (root.pending) {
        root.pending = false
        root.apply()
      }
    }
  }

  WatchedFile {
    id: file
    path: Quickshell.env("HOME") + "/.config/subcult/motion.json"
  }
}
