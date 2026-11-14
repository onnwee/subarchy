pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../widgets/indicators/Model.js" as Model

// Open capture sessions of the compositor's own protocols (wf-recorder over
// wlr-screencopy, toplevel export), which make no PipeWire node. One count
// for the whole shell, kept from Hyprland's `screencast` events, so a bar
// created later (a monitor plugged in, a reloaded widget) still shows a
// recording that started before it. shell.qml references it so it counts
// from shell start.
//
// gpu-screen-recorder reads the screen through KMS, which neither Hyprland
// nor PipeWire sees; `subcult capture recording` sets `recording` over IPC
// while it runs.
Singleton {
  id: root

  property int count: 0
  property bool recording: false

  IpcHandler {
    target: "subcult.screencasts"
    function setRecording(on: bool): void {
      root.recording = on
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "screencast")
        root.count = Model.screencasts(root.count, event.data)
    }
  }
}
