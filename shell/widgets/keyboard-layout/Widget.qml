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

  // A change during a read reads again after it: that read may have
  // started before the change.
  function read() {
    if (query.running)
      query.again = true
    else
      query.running = true
  }

  Process {
    id: query
    property bool again: false
    running: true
    command: ["hyprctl", "devices", "-j"]
    stdout: StdioCollector {
      onStreamFinished: root.code = Model.fromDevices(text, root.eventKeyboard)
    }
    onExited: {
      if (query.again) {
        query.again = false
        Qt.callLater(root.read)
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "activelayout") {
        root.eventKeyboard = Model.eventKeyboard(event.data)
        root.read()
      } else if (event.name === "configreloaded") {
        root.read()
      }
    }
  }
}
