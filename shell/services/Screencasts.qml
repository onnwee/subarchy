pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../widgets/indicators/Model.js" as Model

// Open capture sessions of the compositor's own protocols (wf-recorder over
// wlr-screencopy, toplevel export), which make no PipeWire node. One count
// for the whole shell, kept from Hyprland's `screencast` events, so a bar
// created later (a monitor plugged in, a reloaded widget) still shows a
// recording that started before it. shell.qml references it so it counts
// from shell start.
Singleton {
  id: root

  property int count: 0

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "screencast")
        root.count = Model.screencasts(root.count, event.data)
    }
  }
}
