import QtQuick
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Battery and noise mode of the connected HT3, read from the headset over
// its control channel by `subcult ht3 watch`. The helper starts when this
// panel opens and stops when it closes; audio stays connected throughout.
PanelBase {
  id: panel

  readonly property var adapter: Bluetooth.defaultAdapter // qmllint disable unresolved-type
  readonly property var device: adapter && adapter.devices ? Model.connected(adapter.devices.values) : null
  // The address this panel opened the helper for; empty when none.
  property string held: ""

  // Follow the connected HT3: release the helper when it disconnects, and
  // start it again when it (or another HT3) connects while the panel is open.
  function hold() {
    const address = panel.device ? panel.device.address : ""
    if (address === panel.held)
      return
    if (panel.held !== "")
      Ht3.release()
    panel.held = address
    if (address !== "")
      Ht3.acquire(address)
  }

  onDeviceChanged: hold()
  Component.onCompleted: hold()
  Component.onDestruction: {
    if (panel.held !== "")
      Ht3.release()
  }

  implicitWidth: 280
  implicitHeight: column.implicitHeight

  component Reading: Item {
    id: row
    required property string glyph
    required property string title
    required property string value
    property string name
    height: 30
    Text {
      id: mark
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: 22
      text: row.glyph
      color: Theme.accent
      font.family: Style.fontFamily
      font.pixelSize: Style.iconSize
    }
    Text {
      anchors.left: mark.right
      anchors.leftMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      text: row.title
      color: Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }
    Text {
      objectName: row.name
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: row.value
      textFormat: Text.PlainText
      color: Theme.text
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }
  }

  Column {
    id: column
    width: panel.implicitWidth
    spacing: 4

    Text {
      objectName: "deviceName"
      width: parent.width
      text: panel.device ? Model.label(panel.device) : "No HT3 connected"
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: panel.device ? Theme.text : Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize + 1
      font.bold: panel.device !== null
    }

    Reading {
      visible: panel.held !== "" && panel.device !== null
      width: parent.width
      name: "battery"
      glyph: Glyphs.battery(Math.max(0, Ht3.battery), false)
      title: "Battery"
      value: Model.batteryText(Ht3.battery) || "…"
    }
    Reading {
      visible: panel.held !== "" && panel.device !== null
      width: parent.width
      name: "mode"
      glyph: Glyphs.headphones
      title: "Noise mode"
      value: Model.modeText(Ht3.mode) || "…"
    }

    Text {
      objectName: "status"
      visible: text !== ""
      width: parent.width
      text: panel.held === "" || !panel.device ? "Connect the headphones in the Bluetooth panel."
        : Ht3.message !== "" ? Ht3.message
        : !Ht3.connected ? "Connecting to the headphones…" : ""
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Ht3.message !== "" ? Theme.warning : Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }
  }
}
