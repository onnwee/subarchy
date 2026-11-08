import QtQuick
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui
import "../../Commons/Glyphs.js" as Glyphs

// Bluetooth on, off or connected. Hidden on machines without an adapter.
// A click opens the devices panel; a right click turns the adapter on or
// off.
BarWidget {
  id: root

  readonly property var adapter: Bluetooth.defaultAdapter // qmllint disable unresolved-type
  readonly property int connected: adapter && adapter.devices
    ? adapter.devices.values.filter(d => d.connected).length : 0

  hidden: adapter === null
  implicitWidth: button.implicitWidth

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: root.adapter ? Glyphs.bluetooth(root.adapter.enabled, root.connected) : ""
    color: root.adapter && root.adapter.enabled ? Theme.subtext : Theme.muted
    tooltip: !root.adapter ? "" : !root.adapter.enabled ? "Bluetooth off"
      : root.connected > 0 ? root.connected + " connected" : "Bluetooth on"
    onClicked: (mouse) => {
      if (mouse.button === Qt.RightButton && root.adapter)
        root.adapter.enabled = !root.adapter.enabled
      else
        root.openPanel()
    }
  }
}
