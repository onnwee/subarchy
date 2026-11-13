import QtQuick
import QtQuick.Controls

// SDDM supplies config, userModel, sessionModel, keyboard and sddm. The
// packaged artwork is rendered from the unchanged SUBCULT master (ADR 0052).
// The layout follows the lock screen (lock/LockView.qml): the lockup, the
// clock and the date in one centred column, the fields under them in the
// lock's style (a surface box with a violet edge, green round bullets).
Rectangle {
  id: root
  objectName: "subarchyGreeter"

  readonly property color base: config.base ? config.base : "#100B19"
  readonly property color surface: config.surface ? config.surface : "#1F1830"
  readonly property color borderColor: config.border ? config.border : "#8B5CF6"
  readonly property color borderInactive: config.borderInactive ? config.borderInactive : "#3B2470"
  readonly property color text: config.text ? config.text : "#F0ECE4"
  readonly property color subtext: config.subtext ? config.subtext : "#9A92A8"
  readonly property color muted: config.muted ? config.muted : "#5E5570"
  readonly property color accent: config.accent ? config.accent : "#00FF88"
  readonly property color error: config.error ? config.error : "#D52032"
  // One step of spacing and type: 1 up to 1280x800 logical pixels, growing
  // with the screen to 2 (a 4K screen at scale 1), so the form neither
  // shrinks to a strip on a large screen nor crowds a small one.
  readonly property real unit: Math.max(1, Math.min(2, width / 1280, height / 800))
  // A small window (1280x800 at scale 1.5, 1280x720 at scale 1.25) leaves
  // out the clock, so the form and a two-line message still fit unscrolled.
  readonly property bool compact: width < 640 || height < 600
  property bool authenticating: false
  property bool startingSession: false
  property string message: ""
  // What PAM said during this attempt (faillock's "The account is locked
  // due to 10 failed logins." and "(2 minutes left to unlock)"), shown
  // instead of the general line, as the lock screen does.
  property var pamLines: []
  property bool afterPamText: false
  // SDDM reports Caps Lock only under X11; under Wayland the greeter works
  // it out from the letters typed (an upper-case letter without Shift).
  // Until a letter was typed the state is unknown, and the Caps Lock key
  // alone cannot say which way it went, so the tag stays hidden.
  property bool capsKnown: false
  property bool capsGuess: false
  readonly property bool capsLock: (root.capsKnown && root.capsGuess) || (typeof keyboard !== "undefined" && !!keyboard && keyboard.capsLock === true)

  color: root.base

  function sp(n) {
    return Math.round(n * root.unit)
  }

  function login() {
    if (root.authenticating)
      return
    if (user.text.trim() === "") {
      user.forceActiveFocus()
      return
    }
    root.message = ""
    root.pamLines = []
    root.afterPamText = false
    root.authenticating = true
    sddm.login(user.text.trim(), password.text, sessionModel.lastIndex)
  }

  // Escape: start the password again, without the last attempt's message.
  // In the user field it puts back the last user and stays there.
  function clear(item) {
    if (root.authenticating)
      return
    root.message = ""
    root.pamLines = []
    if (item === user) {
      user.text = userModel.lastUser
      return
    }
    password.text = ""
    password.forceActiveFocus()
  }

  function noteKey(event) {
    if (event.key === Qt.Key_CapsLock) {
      if (root.capsKnown)
        root.capsGuess = !root.capsGuess
      return
    }
    const t = event.text
    if (t.length !== 1 || t.toUpperCase() === t.toLowerCase())
      return
    const shift = (event.modifiers & Qt.ShiftModifier) !== 0
    root.capsGuess = (t === t.toUpperCase()) !== shift
    root.capsKnown = true
  }

  function reveal(item) {
    const top = item.mapToItem(scroller.contentItem, 0, 0).y
    if (top < scroller.contentY + 16)
      scroller.contentY = Math.max(0, top - 16)
    else if (top + item.height > scroller.contentY + scroller.height - 16)
      scroller.contentY = Math.min(scroller.contentHeight - scroller.height, top + item.height - scroller.height + 16)
  }

  // The lock's clock rule: tick just after each minute, whatever the clock did.
  property date now: new Date()
  Timer {
    objectName: "clockTimer"
    running: !root.compact
    repeat: true
    interval: 60050 - (Date.now() % 60000)
    onRunningChanged: {
      if (running) {
        root.now = new Date()
        interval = 60050 - (root.now.getTime() % 60000)
      }
    }
    onTriggered: {
      root.now = new Date()
      interval = 60050 - (root.now.getTime() % 60000)
    }
  }

  // A field in the lock's style; `icon` draws on its left inside the box.
  component Field: TextField {
    id: field
    property Component icon
    width: parent.width
    height: root.sp(44)
    enabled: !root.authenticating
    color: enabled ? root.text : root.muted
    selectionColor: root.borderColor
    selectedTextColor: root.base
    font.family: "monospace"
    font.pixelSize: root.sp(16)
    leftPadding: root.sp(44)
    rightPadding: root.sp(14)
    verticalAlignment: TextInput.AlignVCenter
    background: Rectangle {
      color: root.surface
      border.width: field.activeFocus ? 2 : 1
      border.color: !field.enabled ? root.muted : field.activeFocus ? root.borderColor : root.borderInactive
      Loader {
        x: root.sp(14)
        width: root.sp(20)
        height: root.sp(24)
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: field.icon
      }
    }
    Keys.onPressed: event => root.noteKey(event)
    Keys.onEscapePressed: root.clear(field)
    onActiveFocusChanged: { if (activeFocus) Qt.callLater(() => root.reveal(field)) }
  }

  component FieldLabel: Text {
    property Item field
    readonly property bool focused: !!field && field.activeFocus
    color: focused ? root.text : root.subtext
    font.family: "sans-serif"
    font.pixelSize: root.sp(13)
    font.bold: focused
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

    Column {
      id: layout
      width: Math.min(root.sp(360), scroller.width - 48)
      x: (scroller.width - width) / 2
      y: Math.max(16, (scroller.height - height) / 2)
      spacing: root.sp(28)

      Image {
        objectName: "brandLogo"
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: width * 0.26
        source: "lockup-dark.png"
        sourceSize.width: width * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        Accessible.role: Accessible.Graphic
        Accessible.name: "SUBCULT"
      }

      Column {
        objectName: "clock"
        visible: !root.compact
        width: parent.width
        spacing: root.sp(4)
        Text {
          objectName: "clockTime"
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: ("0" + root.now.getHours()).slice(-2) + ":" + ("0" + root.now.getMinutes()).slice(-2)
          color: root.text
          font.family: "monospace"
          font.pixelSize: root.sp(64)
          font.bold: true
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: Qt.formatDate(root.now, "dddd d MMMM")
          color: root.subtext
          font.family: "sans-serif"
          font.pixelSize: root.sp(18)
        }
      }

      Column {
        id: form
        objectName: "loginForm"
        width: parent.width
        spacing: root.sp(16)

        Column {
          width: parent.width
          spacing: root.sp(6)
          FieldLabel { objectName: "userLabel"; text: "User"; field: user }
          Field {
            id: user
            objectName: "userField"
            text: userModel.lastUser
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            Accessible.name: "User"
            KeyNavigation.tab: password
            KeyNavigation.backtab: submit
            onAccepted: password.forceActiveFocus()
            // A head over shoulders.
            icon: Item {
              Rectangle {
                x: parent.width * 0.3
                width: parent.width * 0.4
                height: width
                radius: width / 2
                color: root.subtext
              }
              Rectangle {
                y: parent.height * 0.45
                width: parent.width
                height: parent.height * 0.45
                radius: width / 3
                color: root.subtext
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: root.sp(6)
          FieldLabel { objectName: "passwordLabel"; text: "Password"; field: password }
          Field {
            id: password
            objectName: "passwordField"
            echoMode: TextInput.Password
            passwordCharacter: "●"
            // The lock's green bullets; hidden while the check runs.
            color: root.authenticating ? "transparent" : root.accent
            rightPadding: capsHint.visible ? capsHint.width + root.sp(22) : root.sp(14)
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            Accessible.name: "Password"
            Accessible.description: root.capsLock ? "Caps Lock is on" : ""
            KeyNavigation.tab: submit
            KeyNavigation.backtab: user
            onAccepted: root.login()
            // The lock's padlock: a shackle behind a body with a keyhole.
            icon: Item {
              Rectangle {
                x: parent.width * 0.2
                y: parent.height * 0.04
                width: parent.width * 0.6
                height: parent.height * 0.7
                radius: width / 2
                color: "transparent"
                border.width: Math.max(2, root.sp(2))
                border.color: root.text
              }
              Rectangle {
                x: parent.width * 0.1
                y: parent.height * 0.42
                width: parent.width * 0.8
                height: parent.height * 0.5
                color: root.text
              }
              Rectangle {
                x: parent.width * 0.45
                y: parent.height * 0.58
                width: parent.width * 0.1
                height: parent.height * 0.2
                color: root.surface
              }
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: parent.leftPadding
              anchors.verticalCenter: parent.verticalCenter
              visible: root.authenticating && !root.startingSession
              text: "Checking…"
              color: root.muted
              font.family: "sans-serif"
              font.pixelSize: root.sp(14)
            }

            Rectangle {
              id: capsHint
              objectName: "capsLockHint"
              visible: root.capsLock && !root.authenticating
              anchors.right: parent.right
              anchors.rightMargin: root.sp(8)
              anchors.verticalCenter: parent.verticalCenter
              width: capsText.implicitWidth + root.sp(12)
              height: capsText.implicitHeight + root.sp(6)
              color: root.borderInactive
              Accessible.role: Accessible.StaticText
              Accessible.name: "Caps Lock is on"
              Text {
                id: capsText
                anchors.centerIn: parent
                text: "Caps Lock"
                color: root.text
                font.family: "sans-serif"
                font.pixelSize: root.sp(12)
                font.bold: true
              }
            }
          }
        }

        Button {
          id: submit
          objectName: "signInButton"
          width: parent.width
          height: root.sp(44)
          enabled: !root.authenticating && user.text.trim() !== ""
          hoverEnabled: true
          Accessible.name: "Sign in"
          KeyNavigation.tab: user
          KeyNavigation.backtab: password
          // Caps Lock pressed here still counts.
          Keys.onPressed: event => root.noteKey(event)
          Keys.onReturnPressed: root.login()
          Keys.onEnterPressed: root.login()
          Keys.onEscapePressed: root.clear(submit)
          contentItem: Text {
            text: root.startingSession ? "Starting desktop…" : root.authenticating ? "Signing in…" : "Sign in"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: submit.enabled ? root.base : root.authenticating ? root.text : root.subtext
            font.family: "sans-serif"
            font.pixelSize: root.sp(16)
            font.bold: true
          }
          background: Rectangle {
            color: root.authenticating ? root.borderInactive : !submit.enabled ? root.surface : submit.down ? Qt.darker(root.borderColor, 1.1) : submit.hovered ? Qt.lighter(root.borderColor, 1.1) : root.borderColor
            border.width: submit.activeFocus ? 2 : 1
            border.color: submit.activeFocus ? root.text : submit.enabled ? root.borderColor : root.borderInactive
          }
          onClicked: root.login()
          onActiveFocusChanged: { if (activeFocus) Qt.callLater(() => root.reveal(submit)) }
        }

        // Two lines stay free for the message (faillock's text takes two),
        // so the form does not move when one appears or clears.
        Item {
          objectName: "messageSlot"
          width: parent.width
          height: Math.max(twoLines.height, root.message === "" ? 0 : errorMessage.height)
          Text { id: twoLines; visible: false; text: "A\nA"; font: errorMessage.font }
          Row {
            width: parent.width
            spacing: root.sp(10)
            visible: root.message !== ""
            Rectangle { width: Math.max(3, root.sp(3)); height: errorMessage.height; color: root.error }
            Text {
              id: errorMessage
              objectName: "loginError"
              width: parent.width - parent.spacing - Math.max(3, root.sp(3))
              text: root.message
              color: root.text
              font.family: "sans-serif"
              font.pixelSize: root.sp(14)
              wrapMode: Text.WordWrap
              Accessible.role: Accessible.AlertMessage
            }
          }
        }
      }

      Text {
        width: parent.width
        text: "Subarchy · " + sddm.hostName
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        color: root.subtext
        font.family: "monospace"
        font.pixelSize: root.sp(13)
      }
    }
  }

  // SDDM sends each PAM error line as informationMessage followed by
  // loginFailed while PAM is still running, then the result of the whole
  // check (pam_strerror's "Authentication failure", in the system
  // language) the same way, then one more loginFailed. A loginFailed right
  // after a PAM line shows the lines so far and keeps the form busy; a
  // loginFailed with no line before it ends the attempt, and the last line
  // was that general result, which says no more than the greeter's own.
  Timer {
    id: settle
    interval: 10000
    onTriggered: root.endAttempt()
  }

  function pamMessage(lines) {
    return lines.filter(line => line !== "").join(" ").slice(0, 300)
  }

  function endAttempt() {
    settle.stop()
    if (!root.authenticating)
      return
    root.authenticating = false
    password.text = ""
    password.forceActiveFocus()
    Qt.callLater(() => root.reveal(errorMessage))
  }

  Connections {
    target: sddm
    function onInformationMessage(message) {
      if (!root.authenticating)
        return
      const line = String(message || "").replace(/[\u0000-\u001f\u007f]+/g, " ").trim()
      root.pamLines = root.pamLines.concat([line])
      root.afterPamText = true
    }
    function onLoginFailed() {
      if (!root.authenticating)
        return
      const general = "That password didn't work. Try again."
      if (root.afterPamText) {
        root.afterPamText = false
        root.message = root.pamMessage(root.pamLines) || general
        settle.restart()
        return
      }
      root.message = root.pamMessage(root.pamLines.slice(0, -1)) || general
      root.endAttempt()
    }
    function onLoginSucceeded() {
      settle.stop()
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
