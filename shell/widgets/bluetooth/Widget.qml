import QtQuick
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui
import "../../Commons/Glyphs.js" as Glyphs

// Bluetooth on, off or connected. Hidden on machines without an adapter.
// Click turns the adapter on or off.
BarWidget {
  id: root

  readonly property var adapter: Bluetooth.defaultAdapter
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
    onClicked: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
  }
}
