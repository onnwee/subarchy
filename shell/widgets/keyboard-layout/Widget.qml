import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The active keyboard layout code. Read once at start and again on each
// Hyprland layout change; nothing polls. Hidden until known.
BarWidget {
  id: root

  property string code: ""

  hidden: code === ""
  implicitWidth: button.implicitWidth

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    label: root.code
    color: Theme.subtext
    tooltip: "Keyboard layout"
  }

  Process {
    id: query
    running: true
    command: ["hyprctl", "devices", "-j"]
    stdout: StdioCollector {
      onStreamFinished: root.code = Model.fromDevices(text)
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "activelayout")
        query.running = true
    }
  }
}
