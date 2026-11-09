import QtQuick
import QtQuick.Controls

// Subarchy's greeter (ADR 0030), a Qt 6 QML theme for SDDM in the SUBCULT
// roles: ink #100B19, surface #1F1830, violet #8B5CF6, paper #F0ECE4, red
// #D52032. `subcult theme apply-system` writes theme.conf beside this file
// with the user's palette (ADR 0037); without it these are the colours. The
// lockup over the last user and a passphrase field; Enter logs into the
// last session (Subarchy's). A failure says so and clears the field.
Rectangle {
  id: root

  readonly property color base: config.base ? config.base : "#100B19"
  readonly property color surface: config.surface ? config.surface : "#1F1830"
  readonly property color borderColor: config.border ? config.border : "#8B5CF6"
  readonly property color borderInactive: config.borderInactive ? config.borderInactive : "#3B2470"
  readonly property color text: config.text ? config.text : "#F0ECE4"
  readonly property color subtext: config.subtext ? config.subtext : "#9A92A8"
  readonly property color muted: config.muted ? config.muted : "#5E5570"
  readonly property color error: config.error ? config.error : "#D52032"

  color: root.base

  function login() {
    if (user.text.trim() === "")
      return
    message.text = ""
    busy.visible = true
    sddm.login(user.text.trim(), password.text, sessionModel.lastIndex)
  }

  Column {
    anchors.centerIn: parent
    width: 320
    spacing: 20

    Image {
      width: parent.width
      source: "lockup-dark.svg"
      sourceSize.width: parent.width
      fillMode: Image.PreserveAspectFit
      smooth: true
    }

    Item {
      width: parent.width
      height: 12
    }

    TextField {
      id: user
      width: parent.width
      text: userModel.lastUser
      placeholderText: "User"
      color: root.text
      placeholderTextColor: root.muted
      font.pixelSize: 15
      leftPadding: 12
      background: Rectangle {
        color: root.surface
        border.width: 1
        border.color: user.activeFocus ? root.borderColor : root.borderInactive
      }
      onAccepted: password.forceActiveFocus()
    }

    TextField {
      id: password
      width: parent.width
      echoMode: TextInput.Password
      placeholderText: "Passphrase"
      color: root.text
      placeholderTextColor: root.muted
      font.pixelSize: 15
      leftPadding: 12
      background: Rectangle {
        color: root.surface
        border.width: 1
        border.color: password.activeFocus ? root.borderColor : root.borderInactive
      }
      onAccepted: root.login()
    }

    Text {
      id: message
      width: parent.width
      text: ""
      color: root.error
      font.pixelSize: 13
      wrapMode: Text.Wrap
      visible: text !== ""
    }

    Text {
      id: busy
      width: parent.width
      text: "Signing in…"
      color: root.subtext
      font.pixelSize: 13
      visible: false
    }
  }

  Text {
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottomMargin: 24
    text: sddm.hostName
    color: root.muted
    font.pixelSize: 12
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      busy.visible = false
      message.text = "That passphrase did not work. Try again."
      password.text = ""
      password.forceActiveFocus()
    }
    function onLoginSucceeded() {
      busy.visible = false
    }
  }

  Component.onCompleted: {
    if (user.text === "")
      user.forceActiveFocus()
    else
      password.forceActiveFocus()
  }
}
