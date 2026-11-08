import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The active keyboard layout code. Read once at start and again on each
// Hyprland layout change and config reload; nothing polls. Hidden until
// known. The keyboard that reported the last layout change is the one
// shown, not whichever device holds Hyprland's `main` flag.
BarWidget {
  id: root

  property string code: ""
  property string eventKeyboard: ""

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
      onStreamFinished: root.code = Model.fromDevices(text, root.eventKeyboard)
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "activelayout") {
        root.eventKeyboard = Model.eventKeyboard(event.data)
        query.running = true
      } else if (event.name === "configreloaded") {
        query.running = true
      }
    }
  }
}
