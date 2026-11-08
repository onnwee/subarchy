pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// The adapter switch and its paired devices, connected first. A click
// connects or disconnects a device; a right click forgets it. Discovery is
// never started from here (pairing is a settings task), so nothing scans.
PanelBase {
  id: panel

  readonly property var adapter: Bluetooth.defaultAdapter // qmllint disable unresolved-type
  readonly property var devices: adapter && adapter.devices ? Model.paired(adapter.devices.values) : []

  implicitWidth: 320
  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: panel.implicitWidth
    spacing: 6

    Item {
      width: parent.width
      height: 24
      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: panel.adapter ? (panel.adapter.enabled ? "Bluetooth on" : "Bluetooth off") : "No Bluetooth adapter"
        color: Theme.subtext
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
      }
      IconButton {
        visible: panel.adapter !== null
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        glyph: Glyphs.bluetooth(panel.adapter ? panel.adapter.enabled : false, 0)
        color: panel.adapter && panel.adapter.enabled ? Theme.accent : Theme.muted
        tooltip: panel.adapter && panel.adapter.enabled ? "Turn off" : "Turn on"
        onClicked: if (panel.adapter) panel.adapter.enabled = !panel.adapter.enabled
      }
    }

    Text {
      visible: panel.adapter !== null && panel.adapter.enabled && panel.devices.length === 0
      width: parent.width
      text: "No paired devices. Pair one with the Bluetooth settings (bluetoothctl)."
      wrapMode: Text.Wrap
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }

    Repeater {
      model: panel.adapter && panel.adapter.enabled ? panel.devices : []
      delegate: Rectangle {
        id: row
        required property var modelData
        width: column.width
        height: 36
        radius: 3
        color: row.modelData.connected ? Theme.selection : "transparent"

        Text {
          id: mark
          anchors.left: parent.left
          anchors.leftMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          text: Glyphs.bluetooth(true, row.modelData.connected ? 1 : 0)
          color: row.modelData.connected ? Theme.accent : Theme.subtext
          font.family: Style.fontFamily
          font.pixelSize: Style.fontSize + 3
        }
        Column {
          anchors.left: mark.right
          anchors.leftMargin: 8
          anchors.right: parent.right
          anchors.rightMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          Text {
            width: parent.width
            text: Model.label(row.modelData)
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.text
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize
          }
          Text {
            width: parent.width
            text: [Model.stateText(row.modelData), Model.batteryText(row.modelData)].filter(s => s !== "").join(" · ")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.subtext
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize - 2
          }
        }
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: (mouse) => {
            const d = row.modelData
            if (mouse.button === Qt.RightButton)
              d.forget()
            else if (Model.action(d) === "connect")
              d.connect()
            else if (Model.action(d) === "disconnect")
              d.disconnect()
          }
        }
      }
    }

    Text {
      visible: panel.adapter !== null
      width: parent.width
      text: "Click connects or disconnects; right click forgets the device."
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 2
    }
  }
}
