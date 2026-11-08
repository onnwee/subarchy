pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "MotionModel.js" as Model

// Whether the interface moves (rice port; ADR 0054): the motion setting
// combined with the power source. Widgets read `enabled` or `duration`
// (0 when motion is off). When the answer changes, the compositor is told
// through `hyprctl eval`, so Hyprland's animations, blur and shadows follow
// the same setting without a reload. Driven by the file watch and UPower;
// nothing polls.
Singleton {
  id: root

  readonly property string systemPath: Quickshell.env("SUBCULT_PATH") || "/usr/share/subcult"
  readonly property string mode: Model.mode(file.text)
  readonly property bool enabled: Model.enabled(mode, Power.onBattery)
  readonly property int duration: enabled ? 160 : 0
  property bool pending: false

  onEnabledChanged: root.apply()

  function apply() {
    if (hyprctl.running)
      root.pending = true
    else
      hyprctl.running = true
  }

  Process {
    id: hyprctl
    command: ["hyprctl", "eval", Model.evalLua(root.systemPath)]
    onExited: {
      if (root.pending) {
        root.pending = false
        running = true
      }
    }
  }

  WatchedFile {
    id: file
    path: Quickshell.env("HOME") + "/.config/subcult/motion.json"
  }
}
