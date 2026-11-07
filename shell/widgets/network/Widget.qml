import QtQuick
import Quickshell.Networking
import qs.Commons
import qs.Ui
import "../../Commons/Glyphs.js" as Glyphs

// The connection in use: wired first, then Wi-Fi with its signal. Driven
// by NetworkManager over D-Bus.
BarWidget {
  id: root

  readonly property var devices: Networking.devices ? Networking.devices.values : []
  readonly property var wired: devices.find(d => d.type === DeviceType.Wired && d.connected) || null
  readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) || null
  readonly property var wifiNetwork: wifiDevice && wifiDevice.networks
    ? (wifiDevice.networks.values.find(n => n.connected) || null) : null

  hidden: devices.length === 0
  implicitWidth: button.implicitWidth

  IconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    glyph: root.wired ? Glyphs.ethernet(true)
      : root.wifiNetwork ? Glyphs.wifi(root.wifiNetwork.signalStrength)
      : root.wifiDevice ? Glyphs.wifiOff() : Glyphs.ethernet(false)
    color: root.wired || root.wifiNetwork ? Theme.subtext : Theme.muted
    tooltip: root.wired ? "Wired" : root.wifiNetwork ? root.wifiNetwork.name : "Not connected"
  }
}
