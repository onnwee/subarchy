pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import qs.Commons
import "PolkitModel.js" as Model

// The polkit authentication agent (ADR 0023): when an app asks for admin
// rights, a centred dialog on the focused output asks for the password.
// The window exists only while a request is open. The field is read-only,
// never disabled, while PAM checks, so it keeps the focus; Escape and
// Enter work wherever the focus is; after a wrong password the field is
// refocused and says so for two seconds.
PanelWindow { // qmllint disable uncreatable-type
  id: dialog

  readonly property var flow: agent.flow // qmllint disable unresolved-type
  readonly property string userName: Quickshell.env("USER")
  property bool wrongPassword: false

  visible: agent.isActive && flow !== null
  screen: place.screen
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
    // The identity to authenticate as, chosen before the first response:
    // the current user when several admins are offered.
    onAuthenticationRequestStarted: {
      const f = agent.flow // qmllint disable unresolved-type
      const ids = f ? Array.from(f.identities || []) : []
      if (ids.length > 0)
        f.selectedIdentity = ids[Model.pickIdentity(ids, dialog.userName)]
    }
  }

  // Another agent (a desktop's own, or a second shell) holding the session
  // is the usual reason registration fails; say so once.
  Timer {
    interval: 5000
    running: true
    onTriggered: if (!agent.isRegistered)
      console.warn("subcult shell: the polkit agent is not registered; another authentication agent probably holds this session")
  }

  Connections {
    target: dialog.flow // qmllint disable unresolved-type
    function onAuthenticationFailed() {
      dialog.wrongPassword = true
      wrongPasswordTimer.restart()
      Qt.callLater(() => password.forceActiveFocus())
    }
  }

  Timer {
    id: wrongPasswordTimer
    interval: 2000
    onTriggered: dialog.wrongPassword = false
  }

  onVisibleChanged: {
    password.text = ""
    dialog.wrongPassword = false
    if (visible) {
      place.open()
      password.forceActiveFocus()
    }
  }

  OverlayScreen {
    id: place
  }

  // PAM asks again after a wrong password: give the field the focus back.
  Connections {
    target: dialog.flow // qmllint disable unresolved-type
    function onIsResponseRequiredChanged() {
      if (dialog.flow && dialog.flow.isResponseRequired)
        password.forceActiveFocus()
    }
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

  FocusScope {
    anchors.fill: parent
    focus: true
    // Escape cancels and Enter submits wherever the focus is.
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: (event) => {
      if (event.key === Qt.Key_Escape) {
        dialog.cancel()
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        dialog.submit()
        event.accepted = true
      }
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
          textFormat: Text.PlainText
          color: Theme.subtext
          wrapMode: Text.Wrap
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize
        }
        Text {
          width: parent.width
          visible: text !== ""
          text: dialog.flow ? dialog.flow.supplementaryMessage : ""
          textFormat: Text.PlainText
          color: dialog.flow && dialog.flow.supplementaryIsError ? Theme.error : Theme.subtext
          wrapMode: Text.Wrap
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize
        }
        Text {
          width: parent.width
          visible: dialog.wrongPassword
          text: "Wrong password, try again."
          color: Theme.error
          font.family: Style.uiFontFamily
          font.pixelSize: Style.fontSize
        }
        TextField {
          id: password
          width: parent.width
          placeholderText: dialog.flow ? dialog.flow.inputPrompt : "Password"
          echoMode: dialog.flow && dialog.flow.responseVisible ? TextInput.Normal : TextInput.Password
          // Read-only, not disabled, while PAM checks: a disabled field
          // drops the focus, and after a wrong password typing must work
          // without a click.
          readOnly: dialog.flow === null || !dialog.flow.isResponseRequired
          color: Theme.text
          font.family: Style.fontFamily
          font.pixelSize: Style.fontSize + 1
          background: Rectangle {
            color: Theme.base
            border.width: 1
            border.color: password.activeFocus ? Theme.accent : Theme.surface
          }
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
            enabled: !password.readOnly
            onClicked: dialog.submit()
          }
        }
      }
    }
  }
}
