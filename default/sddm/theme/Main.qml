import QtQuick
import QtQuick.Controls

// SDDM supplies config, userModel, sessionModel and sddm. The packaged
// artwork is rendered from the unchanged SUBCULT master (ADR 0052).
Rectangle {
  id: root
  objectName: "subarchyGreeter"

  readonly property color base: config.base ? config.base : "#100B19"
  readonly property color surface: config.surface ? config.surface : "#1F1830"
  readonly property color borderColor: config.border ? config.border : "#8B5CF6"
  readonly property color borderInactive: config.borderInactive ? config.borderInactive : "#3B2470"
  readonly property color text: config.text ? config.text : "#F0ECE4"
  readonly property color subtext: config.subtext ? config.subtext : "#9A92A8"
  readonly property color error: config.error ? config.error : "#D52032"
  readonly property bool compact: width < 1000
  property bool authenticating: false
  property bool startingSession: false
  property string message: ""

  color: root.base

  function login() {
    if (root.authenticating)
      return
    if (user.text.trim() === "") {
      user.forceActiveFocus()
      return
    }
    root.message = ""
    root.authenticating = true
    sddm.login(user.text.trim(), password.text, sessionModel.lastIndex)
  }

  function reveal(item) {
    const top = item.mapToItem(scroller.contentItem, 0, 0).y
    if (top < scroller.contentY + 16)
      scroller.contentY = Math.max(0, top - 16)
    else if (top + item.height > scroller.contentY + scroller.height - 16)
      scroller.contentY = Math.min(scroller.contentHeight - scroller.height, top + item.height - scroller.height + 16)
  }

  Flickable {
    id: scroller
    objectName: "loginScroller"
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: Math.max(height, layout.y + layout.height + 16)
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Grid {
      id: layout
      width: Math.min(1040, scroller.width - 48)
      x: (scroller.width - width) / 2
      y: Math.max(16, (scroller.height - height) / 2)
      columns: root.compact ? 1 : 2
      columnSpacing: 80
      rowSpacing: 24

      Item {
        width: root.compact ? layout.width : layout.width - form.width - layout.columnSpacing
        height: root.compact ? identity.height : form.height

        Column {
          id: identity
          anchors.centerIn: parent
          width: parent.width
          spacing: 8

          Image {
            objectName: "brandLogo"
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(root.compact ? 320 : 480, parent.width)
            height: width * 0.26
            source: "lockup-dark.png"
            sourceSize.width: width * 2
            fillMode: Image.PreserveAspectFit
            smooth: true
            Accessible.role: Accessible.Graphic
            Accessible.name: "SUBCULT"
          }

          Text {
            width: parent.width
            text: "Subarchy"
            horizontalAlignment: Text.AlignHCenter
            color: root.subtext
            font.family: "monospace"
            font.pixelSize: 14
          }
        }
      }

      Column {
        id: form
        objectName: "loginForm"
        width: root.compact ? layout.width : 360
        spacing: 16

        Column {
          width: parent.width
          spacing: 8
          Text {
            text: "Sign in"
            color: root.text
            font.family: "Oswald"
            font.bold: true
            font.pixelSize: 36
          }
          Text {
            width: parent.width
            text: sddm.hostName
            elide: Text.ElideRight
            color: root.subtext
            font.family: "monospace"
            font.pixelSize: 14
          }
        }

        Column {
          width: parent.width
          spacing: 8
          Text {
            text: "User"
            color: root.subtext
            font.family: "monospace"
            font.pixelSize: 13
          }
          TextField {
            id: user
            objectName: "userField"
            width: parent.width
            height: 48
            text: userModel.lastUser
            enabled: !root.authenticating
            color: root.text
            selectionColor: root.borderColor
            selectedTextColor: root.base
            font.family: "monospace"
            font.pixelSize: 16
            leftPadding: 14
            rightPadding: 14
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            Accessible.name: "User"
            KeyNavigation.tab: password
            KeyNavigation.backtab: submit
            background: Rectangle {
              color: root.surface
              border.width: user.activeFocus ? 2 : 1
              border.color: user.activeFocus ? root.borderColor : root.borderInactive
            }
            onAccepted: password.forceActiveFocus()
            onActiveFocusChanged: { if (activeFocus) Qt.callLater(() => root.reveal(user)) }
          }
        }

        Column {
          width: parent.width
          spacing: 8
          Text {
            text: "Password"
            color: root.subtext
            font.family: "monospace"
            font.pixelSize: 13
          }
          TextField {
            id: password
            objectName: "passwordField"
            width: parent.width
            height: 48
            echoMode: TextInput.Password
            enabled: !root.authenticating
            color: root.text
            selectionColor: root.borderColor
            selectedTextColor: root.base
            font.family: "monospace"
            font.pixelSize: 16
            leftPadding: 14
            rightPadding: 14
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            Accessible.name: "Password"
            KeyNavigation.tab: submit
            KeyNavigation.backtab: user
            background: Rectangle {
              color: root.surface
              border.width: password.activeFocus ? 2 : 1
              border.color: password.activeFocus ? root.borderColor : root.borderInactive
            }
            onAccepted: root.login()
            onActiveFocusChanged: { if (activeFocus) Qt.callLater(() => root.reveal(password)) }
          }
        }

        Button {
          id: submit
          objectName: "signInButton"
          width: parent.width
          height: 48
          enabled: !root.authenticating && user.text.trim() !== ""
          hoverEnabled: true
          Accessible.name: "Sign in"
          KeyNavigation.tab: user
          KeyNavigation.backtab: password
          contentItem: Text {
            text: root.startingSession ? "Starting desktop…" : root.authenticating ? "Signing in…" : "Sign in"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: submit.enabled ? root.base : root.subtext
            font.family: "monospace"
            font.pixelSize: 16
            font.bold: true
          }
          background: Rectangle {
            color: !submit.enabled ? root.surface : submit.down ? Qt.darker(root.borderColor, 1.1) : submit.hovered ? Qt.lighter(root.borderColor, 1.1) : root.borderColor
            border.width: submit.activeFocus ? 2 : 1
            border.color: submit.activeFocus ? root.text : root.borderColor
          }
          onClicked: root.login()
          onActiveFocusChanged: { if (activeFocus) Qt.callLater(() => root.reveal(submit)) }
        }

        Row {
          width: parent.width
          spacing: 10
          visible: root.message !== ""
          Rectangle { width: 3; height: errorMessage.height; color: root.error }
          Text {
            id: errorMessage
            objectName: "loginError"
            width: parent.width - 13
            text: root.message
            color: root.text
            font.family: "monospace"
            font.pixelSize: 14
            wrapMode: Text.WordWrap
            Accessible.role: Accessible.AlertMessage
          }
        }
      }
    }
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.authenticating = false
      root.message = "That password didn't work. Try again."
      password.text = ""
      password.forceActiveFocus()
      Qt.callLater(() => root.reveal(errorMessage))
    }
    function onLoginSucceeded() {
      root.startingSession = true
      password.text = ""
    }
  }

  Component.onCompleted: {
    if (user.text === "")
      user.forceActiveFocus()
    else
      password.forceActiveFocus()
  }
}
