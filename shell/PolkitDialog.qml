pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import qs.Commons

// The polkit authentication agent (ADR 0023): when an app asks for admin
// rights, a centred dialog on the focused output asks for the password.
// The window exists only while a request is open.
PanelWindow { // qmllint disable uncreatable-type
  id: dialog

  readonly property var flow: agent.flow

  visible: agent.isActive && flow !== null
  screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
  WlrLayershell.namespace: "subcult-polkit"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: Qt.rgba(0, 0, 0, 0.5)

  PolkitAgent {
    id: agent
  }

  onVisibleChanged: {
    password.text = ""
    if (visible)
      password.forceActiveFocus()
  }

  function submit() {
    if (dialog.flow && dialog.flow.isResponseRequired) {
      dialog.flow.submit(password.text)
      password.text = ""
    }
  }

  function cancel() {
    if (dialog.flow)
      dialog.flow.cancelAuthenticationRequest()
  }

  Rectangle {
    anchors.centerIn: parent
    width: 420
    height: content.implicitHeight + 3 * Style.spacing
    color: Theme.mantle
    border.width: 1
    border.color: Theme.border

    Column {
      id: content
      x: 1.5 * Style.spacing
      y: 1.5 * Style.spacing
      width: parent.width - 3 * Style.spacing
      spacing: Style.spacing

      Text {
        width: parent.width
        text: "Authentication required"
        color: Theme.text
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize + 3
        font.bold: true
      }
      Text {
        width: parent.width
        text: dialog.flow ? dialog.flow.message : ""
        color: Theme.subtext
        wrapMode: Text.Wrap
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
      }
      Text {
        width: parent.width
        visible: text !== ""
        text: dialog.flow ? dialog.flow.supplementaryMessage : ""
        color: dialog.flow && dialog.flow.supplementaryIsError ? Theme.error : Theme.subtext
        wrapMode: Text.Wrap
        font.family: Style.uiFontFamily
        font.pixelSize: Style.fontSize
      }
      TextField {
        id: password
        width: parent.width
        placeholderText: dialog.flow ? dialog.flow.inputPrompt : "Password"
        echoMode: dialog.flow && dialog.flow.responseVisible ? TextInput.Normal : TextInput.Password
        enabled: dialog.flow !== null && dialog.flow.isResponseRequired
        color: Theme.text
        font.family: Style.fontFamily
        font.pixelSize: Style.fontSize + 1
        background: Rectangle {
          color: Theme.base
          border.width: 1
          border.color: password.activeFocus ? Theme.accent : Theme.surface
        }
        onAccepted: dialog.submit()
        Keys.onEscapePressed: dialog.cancel()
      }
      Row {
        anchors.right: parent.right
        spacing: Style.spacing
        Button {
          text: "Cancel"
          onClicked: dialog.cancel()
        }
        Button {
          text: "Authenticate"
          enabled: password.enabled
          onClicked: dialog.submit()
        }
      }
    }
  }
}
