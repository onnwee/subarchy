pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Networking
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Wired link, the Wi-Fi switch and the Wi-Fi networks NetworkManager sees:
// the connected one first, then known ones, then by signal. A click joins
// a known or open network (or disconnects the connected one); a new
// secured network asks for its password. The Wi-Fi scanner runs only
// while this panel is open.
PanelBase {
  id: panel

  readonly property var devices: Networking.devices ? Networking.devices.values : [] // qmllint disable missing-property
  readonly property var wired: devices.find(d => d.type === DeviceType.Wired) || null
  readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi) || null
  readonly property var networks: wifi && wifi.networks ? Model.sortNetworks(wifi.networks.values) : []
  // The new secured network whose password is being typed.
  property var asking: null
  // Why the typed password was not used; cleared when the prompt closes.
  property string pskError: ""
  onAskingChanged: panel.pskError = ""

  implicitWidth: 340
  implicitHeight: column.implicitHeight

  // Scan while open, never while closed (ADR 0054).
  Component.onCompleted: if (panel.wifi) panel.wifi.scannerEnabled = true // qmllint disable missing-property
  Component.onDestruction: if (panel.wifi) panel.wifi.scannerEnabled = false // qmllint disable missing-property

  function tap(n) {
    if (n.connected) {
      n.disconnect()
      return
    }
    if (Model.joinable(n)) {
      panel.asking = null
      n.connect()
    } else if (Model.needsPassword(n)) {
      panel.asking = n
      password.text = ""
      password.forceActiveFocus()
    }
  }

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
        text: panel.wired ? (panel.wired.connected ? "Wired: connected" + (panel.wired.linkSpeed ? ", " + panel.wired.linkSpeed + " Mb/s" : "")
          : panel.wired.hasLink ? "Wired: link, not connected" : "Wired: no cable") : "No wired adapter" // qmllint disable missing-property
        color: Theme.subtext
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
      }
      IconButton {
        visible: panel.wifi !== null
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        glyph: Networking.wifiEnabled ? Glyphs.wifi(1) : Glyphs.wifiOff()
        color: Networking.wifiEnabled ? Theme.accent : Theme.muted
        tooltip: Networking.wifiEnabled ? "Wi-Fi on (click to turn off)" : "Wi-Fi off (click to turn on)"
        onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
      }
    }

    Text {
      visible: panel.wifi === null
      text: "No Wi-Fi adapter"
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }
    Text {
      visible: panel.wifi !== null && Networking.wifiEnabled && panel.networks.length === 0
      text: "Looking for networks…"
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }

    Repeater {
      model: Networking.wifiEnabled ? panel.networks.slice(0, 12) : []
      delegate: Rectangle {
        id: row
        required property var modelData
        width: column.width
        height: 36
        radius: 3
        color: row.modelData.connected ? Theme.selection : "transparent"

        Text {
          id: signal
          anchors.left: parent.left
          anchors.leftMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          text: Glyphs.wifi(row.modelData.signalStrength)
          color: row.modelData.connected ? Theme.accent : Theme.subtext
          font.family: Style.fontFamily
          font.pixelSize: Style.fontSize + 3
        }
        Column {
          anchors.left: signal.right
          anchors.leftMargin: 8
          anchors.right: parent.right
          anchors.rightMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          Text {
            width: parent.width
            text: row.modelData.name
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.text
            font.family: Style.uiFontFamily
            font.pixelSize: Style.fontSize
          }
          Text {
            width: parent.width
            text: [Model.securityText(row.modelData.security), Model.signalText(row.modelData.signalStrength), Model.stateText(row.modelData)].filter(s => s !== "").join(" · ")
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
            if (mouse.button === Qt.RightButton && row.modelData.known)
              row.modelData.forget()
            else
              panel.tap(row.modelData)
          }
        }
      }
    }

    // The password for a new secured network; Enter joins, Escape cancels.
    // A password under 8 characters keeps the prompt open with a hint.
    Rectangle {
      visible: panel.asking !== null
      width: parent.width
      height: visible ? 60 + (pskHint.visible ? pskHint.implicitHeight + 4 : 0) : 0
      color: Theme.base
      border.width: 1
      border.color: Theme.surface
      Column {
        x: 8
        y: 6
        width: parent.width - 16
        spacing: 4
        Text {
          text: panel.asking ? "Password for " + panel.asking.name : ""
          textFormat: Text.PlainText
          color: Theme.subtext
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 1
        }
        TextInput {
          id: password
          width: parent.width
          height: 24
          echoMode: TextInput.Password
          color: Theme.text
          selectionColor: Theme.selection
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize
          onAccepted: {
            if (panel.asking && text.length < 8) {
              panel.pskError = "At least 8 characters"
              return
            }
            if (panel.asking)
              panel.asking.connectWithPsk(text) // qmllint disable missing-property
            panel.asking = null
            text = ""
          }
          Keys.onEscapePressed: {
            panel.asking = null
            text = ""
          }
        }
        Text {
          id: pskHint
          visible: panel.pskError !== ""
          text: panel.pskError
          color: Theme.error
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize - 2
        }
      }
    }

    Text {
      visible: panel.wifi !== null
      width: parent.width
      text: "Click joins or leaves; right click forgets a saved network."
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 2
    }
  }
}
