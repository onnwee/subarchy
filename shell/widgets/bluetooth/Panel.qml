pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui
import qs.services
import "Model.js" as Model
import "../../Commons/Glyphs.js" as Glyphs

// Paired controls plus a bounded, user-started search and native pairing
// prompts. Closing the panel ends its agent and only the scan it started.
PanelBase {
  id: panel

  readonly property var adapter: Bluetooth.defaultAdapter // qmllint disable unresolved-type
  readonly property var devices: adapter && adapter.devices ? Model.paired(adapter.devices.values) : []
  readonly property var nearby: adapter && adapter.devices ? Model.nearby(adapter.devices.values) : []
  readonly property var pairing: BluetoothPairing
  property bool searching: false
  property var scanAdapter: null

  function stopSearch() {
    const previous = panel.scanAdapter
    panel.scanAdapter = null
    panel.searching = false
    searchTimeout.stop()
    // A removed adapter has already lost its discovery lease in BlueZ.
    if (previous) {
      try { previous.discovering = false } catch (e) { /* adapter disappeared */ }
    }
  }

  function search() {
    if (!panel.adapter || !panel.adapter.enabled || !BluetoothPairing.ready || BluetoothPairing.busy)
      return
    if (!panel.adapter.discovering) {
      panel.scanAdapter = panel.adapter
      panel.adapter.discovering = true
    }
    panel.searching = true
    searchTimeout.restart()
  }

  function pairDevice(device) {
    const path = device.dbusPath
    const name = Model.label(device)
    panel.stopSearch()
    BluetoothPairing.pair(path, name)
  }

  onAdapterChanged: stopSearch()
  Connections {
    target: panel.adapter
    function onEnabledChanged() {
      if (!panel.adapter || !panel.adapter.enabled)
        panel.stopSearch()
    }
  }
  Component.onCompleted: BluetoothPairing.acquire()
  Component.onDestruction: {
    stopSearch()
    BluetoothPairing.release()
  }

  Timer { id: searchTimeout; interval: 30000; onTriggered: panel.stopSearch() }

  component ActionButton: Button {
    id: control
    height: 32
    font.family: Style.uiFontFamily
    font.pixelSize: Style.fontSize - 1
    contentItem: Text {
      text: control.text
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      color: control.enabled ? Theme.text : Theme.muted
      font: control.font
    }
    background: Rectangle {
      radius: 3
      color: control.down ? Theme.selection : Theme.surface
      border.width: 1
      border.color: control.activeFocus ? Theme.accent : Theme.surface
    }
  }

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
        visible: panel.adapter !== null && BluetoothPairing.request === null
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        glyph: Glyphs.bluetooth(panel.adapter ? panel.adapter.enabled : false, 0)
        color: panel.adapter && panel.adapter.enabled ? Theme.accent : Theme.muted
        tooltip: panel.adapter && panel.adapter.enabled ? "Turn off" : "Turn on"
        onClicked: if (panel.adapter) panel.adapter.enabled = !panel.adapter.enabled
      }
    }

    Text {
      visible: panel.adapter !== null && panel.adapter.enabled && panel.devices.length === 0 && !BluetoothPairing.busy
      width: parent.width
      text: "No paired devices. Put a device in pairing mode, then search below."
      wrapMode: Text.Wrap
      color: Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }

    Repeater {
      model: panel.adapter && panel.adapter.enabled && BluetoothPairing.request === null ? panel.devices : []
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
      visible: panel.adapter !== null && BluetoothPairing.request === null
      width: parent.width
      text: "Click connects or disconnects; right click forgets the device."
      color: Theme.muted
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize - 2
    }

    ActionButton {
      objectName: "searchDevices"
      visible: panel.adapter !== null && panel.adapter.enabled
      width: parent.width
      enabled: BluetoothPairing.ready && !BluetoothPairing.busy
      text: panel.searching ? "Stop searching" : BluetoothPairing.ready ? "Search for a device" : "Preparing pairing…"
      onClicked: panel.searching ? panel.stopSearch() : panel.search()
    }

    ListView {
      id: nearbyList
      objectName: "nearbyDevices"
      visible: panel.searching
      width: parent.width
      height: visible ? Math.min(220, contentHeight) : 0
      clip: true
      model: panel.searching ? panel.nearby : []
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      delegate: Item {
        id: candidate
        required property var modelData
        width: nearbyList.width
        height: 44
        Text {
          anchors.left: parent.left
          anchors.right: pairButton.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          text: Model.label(candidate.modelData)
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Theme.text
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize
        }
        ActionButton {
          id: pairButton
          objectName: "pairDevice"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 126
          text: "Pair and trust"
          enabled: BluetoothPairing.ready && !BluetoothPairing.busy
          Accessible.name: "Pair and trust " + Model.label(candidate.modelData)
          onClicked: panel.pairDevice(candidate.modelData)
        }
      }
    }

    Text {
      visible: panel.searching && panel.nearby.length === 0
      width: parent.width
      text: "Looking for devices…"
      color: Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }

    Column {
      visible: BluetoothPairing.request !== null
      width: parent.width
      spacing: 10
      Text {
        width: parent.width
        text: Model.promptText(BluetoothPairing.request, BluetoothPairing.deviceName)
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Theme.text
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
      }
      Text {
        visible: BluetoothPairing.request !== null && BluetoothPairing.request.code !== undefined
        text: BluetoothPairing.request && BluetoothPairing.request.code ? BluetoothPairing.request.code : ""
        textFormat: Text.PlainText
        color: Theme.accent
        font.family: Style.fontFamily
        font.pixelSize: 26
      }
      TextField {
        id: codeInput
        objectName: "pairingCode"
        visible: BluetoothPairing.request !== null && ["pin", "passkey"].indexOf(BluetoothPairing.request.kind) >= 0
        width: parent.width
        height: 36
        echoMode: TextInput.Password
        color: Theme.text
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
        maximumLength: BluetoothPairing.request && BluetoothPairing.request.kind === "passkey" ? 6 : 16
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
        Accessible.name: "Device PIN or passkey"
        background: Rectangle { color: Theme.surface; border.color: Theme.accent; border.width: 1 }
        onAccepted: BluetoothPairing.respond(true, text)
      }
      Text {
        visible: BluetoothPairing.request !== null && BluetoothPairing.request.kind === "display-passkey"
        text: BluetoothPairing.request ? Math.min(6, Math.max(0, Number(BluetoothPairing.request.entered) || 0)) + " of 6 digits entered" : ""
        color: Theme.subtext
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize - 1
      }
      Row {
        spacing: 8
        ActionButton {
          objectName: "acceptPairing"
          width: 156
          visible: BluetoothPairing.request !== null && ["display-pin", "display-passkey"].indexOf(BluetoothPairing.request.kind) < 0
          text: BluetoothPairing.request && BluetoothPairing.request.kind === "confirmation" ? "Matches" : codeInput.visible ? "Submit" : "Allow"
          onClicked: BluetoothPairing.respond(true, codeInput.text)
        }
        ActionButton {
          objectName: "cancelPairing"
          width: 156
          text: "Cancel"
          onClicked: BluetoothPairing.cancel()
        }
      }
    }

    ActionButton {
      objectName: "cancelWaitingPairing"
      visible: BluetoothPairing.busy && BluetoothPairing.request === null
      width: parent.width
      text: "Cancel pairing"
      onClicked: BluetoothPairing.cancel()
    }

    Text {
      objectName: "pairingStatus"
      visible: BluetoothPairing.message !== ""
      width: parent.width
      text: BluetoothPairing.message
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: Theme.subtext
      font.family: Style.uiFontFamily
      font.pixelSize: Style.fontSize
    }

    Connections {
      target: BluetoothPairing
      function onRequestChanged() {
        codeInput.text = ""
        Qt.callLater(() => { if (codeInput.visible) codeInput.forceActiveFocus() })
      }
    }
  }
}
