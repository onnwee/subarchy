import QtQuick
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// TOZO HT3 headphones. In the bar only while an HT3 is connected over
// Bluetooth (BlueZ pushes the change; nothing polls). A click opens the
// panel, which reads battery and noise mode from the headset.
BarWidget {
  id: root

  readonly property var adapter: Bluetooth.defaultAdapter // qmllint disable unresolved-type
  readonly property var device: adapter && adapter.devices ? Model.connected(adapter.devices.values) : null
  readonly property int bluezBattery: Model.bluezBattery(device)

  hidden: device === null
  implicitWidth: button.implicitWidth

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: Glyphs.headphones
    color: Theme.subtext
    tooltip: root.device ? Model.label(root.device) + (root.bluezBattery >= 0 ? " " + Model.batteryText(root.bluezBattery) : "") : ""
    onClicked: root.openPanel()
  }
}
