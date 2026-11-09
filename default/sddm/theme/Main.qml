import QtQuick
import QtQuick.Controls

// Subarchy's greeter (ADR 0030), a Qt 6 QML theme for SDDM in the SUBCULT
// roles: ink #100B19, surface #1F1830, violet #8B5CF6, paper #F0ECE4, red
// #D52032. The lockup over the last user and a passphrase field; Enter logs
// into the last session (Subarchy's). A failure says so and clears the field.
Rectangle {
  id: root

  color: "#100B19"

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
      color: "#F0ECE4"
      placeholderTextColor: "#5E5570"
      font.pixelSize: 15
      leftPadding: 12
      background: Rectangle {
        color: "#1F1830"
        border.width: 1
        border.color: user.activeFocus ? "#8B5CF6" : "#3B2470"
      }
      onAccepted: password.forceActiveFocus()
    }

    TextField {
      id: password
      width: parent.width
      echoMode: TextInput.Password
      placeholderText: "Passphrase"
      color: "#F0ECE4"
      placeholderTextColor: "#5E5570"
      font.pixelSize: 15
      leftPadding: 12
      background: Rectangle {
        color: "#1F1830"
        border.width: 1
        border.color: password.activeFocus ? "#8B5CF6" : "#3B2470"
      }
      onAccepted: root.login()
    }

    Text {
      id: message
      width: parent.width
      text: ""
      color: "#D52032"
      font.pixelSize: 13
      wrapMode: Text.Wrap
      visible: text !== ""
    }

    Text {
      id: busy
      width: parent.width
      text: "Signing in…"
      color: "#9A92A8"
      font.pixelSize: 13
      visible: false
    }
  }

  Text {
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottomMargin: 24
    text: sddm.hostName
    color: "#5E5570"
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
